
import { Podcast, Episode, RadioStation } from '../types';

const ITUNES_SEARCH_URL = 'https://itunes.apple.com/search';
const ITUNES_LOOKUP_URL = 'https://itunes.apple.com/lookup';
const RADIO_API_BASE = 'https://de1.api.radio-browser.info/json/stations';

export interface UnifiedSearchResults {
  podcasts: Podcast[];
  radio: RadioStation[];
  episodes: Episode[];
}

const TOP_RADIOS: Record<string, string[]> = {
  'fr': ['RTL', 'RTL2', 'Fun Radio', 'France Inter', 'France Info', 'France Culture', 'Europe 1', 'Europe 2', 'RFM', 'RMC', 'NRJ', 'Nostalgie', 'Skyrock', 'FIP'],
  'en': ['BBC World Service', 'NPR', 'CNN', 'WNYC'],
};

const deduplicateStations = (stations: RadioStation[]): RadioStation[] => {
  const seenBrands = new Map<string, RadioStation>();
  stations.forEach(station => {
    const normalized = station.name.toLowerCase().split(' - ')[0].split(' (')[0].split(' [')[0].replace(/[0-9]+kbps/g, '').replace(/fm$/g, '').trim();
    const existing = seenBrands.get(normalized);
    if (!existing || (station.clickcount || 0) > (existing.clickcount || 0)) {
      seenBrands.set(normalized, station);
    }
  });
  return Array.from(seenBrands.values());
};

const sortStations = (stations: RadioStation[], langCode: string): RadioStation[] => {
  const deduplicated = deduplicateStations(stations);
  const tops = TOP_RADIOS[langCode] || [];
  return [...deduplicated].sort((a, b) => {
    const aName = a.name.toLowerCase();
    const bName = b.name.toLowerCase();
    let aPriority = tops.findIndex(t => aName.includes(t.toLowerCase()));
    let bPriority = tops.findIndex(t => bName.includes(t.toLowerCase()));
    if (aPriority !== -1 && bPriority !== -1) return aPriority - bPriority;
    if (aPriority !== -1) return -1;
    if (bPriority !== -1) return 1;
    return (b.clickcount || 0) - (a.clickcount || 0);
  });
};

export const getPodcastsByIds = async (ids: number[], country: string = 'us'): Promise<Podcast[]> => {
  if (ids.length === 0) return [];
  try {
    const url = `${ITUNES_LOOKUP_URL}?id=${ids.join(',')}&country=${country}&_v=${Date.now()}`;
    const response = await fetch(url);
    const data = await response.json();
    return data.results || [];
  } catch (error) { return []; }
};

export const matchPodcastOnItunes = async (name: string, publisher: string, country: string = 'us'): Promise<Podcast | null> => {
  try {
    const term = `${name} ${publisher}`;
    const url = `${ITUNES_SEARCH_URL}?term=${encodeURIComponent(term)}&entity=podcast&limit=1&country=${country}`;
    const response = await fetch(url);
    const data = await response.json();
    if (data.results && data.results.length > 0) {
      return data.results[0];
    }
    
    // Fallback: search only by name
    const fallbackUrl = `${ITUNES_SEARCH_URL}?term=${encodeURIComponent(name)}&entity=podcast&limit=5&country=${country}`;
    const fallbackResponse = await fetch(fallbackUrl);
    const fallbackData = await fallbackResponse.json();
    if (fallbackData.results && fallbackData.results.length > 0) {
      const nameLower = name.toLowerCase();
      const bestMatch = fallbackData.results.find((r: any) => {
        const title = (r.collectionName || '').toLowerCase();
        return title.includes(nameLower) || nameLower.includes(title);
      });
      return bestMatch || fallbackData.results[0];
    }
    return null;
  } catch (e) {
    return null;
  }
};

export const getRadioStationsByIds = async (uuids: string[]): Promise<RadioStation[]> => {
  if (uuids.length === 0) return [];
  try {
    const url = `${RADIO_API_BASE}/byuuid?uuids=${uuids.join(',')}`;
    const response = await fetch(url);
    const data = await response.json();
    return data.map((station: any) => ({
      id: station.stationuuid,
      name: station.name,
      url: station.url_resolved,
      favicon: station.favicon || `https://api.dicebear.com/9.x/shapes/svg?seed=${encodeURIComponent(station.name)}`,
      tags: station.tags,
      country: station.country,
      clickcount: station.clickcount
    }));
  } catch (error) { return []; }
};

export const decodeHTMLEntities = (str: string): string => {
  const entities: Record<string, string> = {
    '&amp;': '&',
    '&apos;': "'",
    '&quot;': '"',
    '&lt;': '<',
    '&gt;': '>',
    '&#39;': "'",
    '&#039;': "'",
    '&#x27;': "'",
    '&nbsp;': ' ',
    '&rdquo;': '”',
    '&ldquo;': '“',
    '&lsquo;': '‘',
    '&rsquo;': '’',
    '&ndash;': '–',
    '&mdash;': '—',
    '&#8211;': '–',
    '&#8217;': '’',
    '&#8216;': '‘',
    '&#8220;': '“',
    '&#8221;': '”'
  };
  return str.replace(/&[#\w\d]+;/g, (match) => entities[match] || match);
};

export const parseRSSFeed = (xmlText: string, collectionId: number): Episode[] => {
  const items = xmlText.match(/<item>([\s\S]*?)<\/item>/g) || [];
  const episodes: Episode[] = [];
  
  const channelTitleMatch = xmlText.match(/<channel>[\s\S]*?<title>([\s\S]*?)<\/title>/i);
  const collectionName = channelTitleMatch ? decodeHTMLEntities(channelTitleMatch[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim()) : 'Podcast';

  items.forEach((block, index) => {
    const extractTag = (tag: string): string => {
      const match = block.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, 'i')) ||
                    block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, 'i'));
      if (!match) return '';
      return match[1].replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim();
    };

    const title = extractTag('title') || extractTag('itunes:title');
    const description = extractTag('description') || extractTag('itunes:summary') || extractTag('content:encoded');
    const pubDate = extractTag('pubDate');
    
    const enclosureMatch = block.match(/<enclosure[^>]+url="([^"]+)"/i);
    const previewUrl = enclosureMatch ? enclosureMatch[1] : '';
    
    const durationMatch = block.match(/<itunes:duration>([\s\S]*?)<\/itunes:duration>/i);
    const durationStr = durationMatch ? durationMatch[1].trim() : '';
    let trackTimeMillis = 0;
    if (durationStr) {
      if (durationStr.includes(':')) {
        const parts = durationStr.split(':').map(Number);
        if (parts.length === 3) {
          trackTimeMillis = ((parts[0] * 3600) + (parts[1] * 60) + parts[2]) * 1000;
        } else if (parts.length === 2) {
          trackTimeMillis = ((parts[0] * 60) + parts[1]) * 1000;
        }
      } else {
        trackTimeMillis = Number(durationStr) * 1000;
      }
    }
    
    const imageMatch = block.match(/<itunes:image[^>]+href="([^"]+)"/i) || block.match(/<image[^>]+href="([^"]+)"/i);
    const artworkUrl = imageMatch ? imageMatch[1] : '';
    
    let trackId = collectionId * 1000 + index;
    if (previewUrl) {
      trackId = previewUrl.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0) + index;
    }
    
    if (previewUrl) {
      episodes.push({
        trackId,
        trackName: decodeHTMLEntities(title),
        description: decodeHTMLEntities(description.replace(/<[^>]*>/g, '')),
        releaseDate: pubDate ? new Date(pubDate).toISOString() : new Date().toISOString(),
        previewUrl,
        trackTimeMillis: trackTimeMillis || 1800000, 
        artworkUrl60: artworkUrl,
        artworkUrl160: artworkUrl,
        artworkUrl600: artworkUrl,
        collectionName,
        collectionId
      });
    }
  });
  
  return episodes;
};

const fetchFeed = async (feedUrl: string, bypassCache = false): Promise<string | null> => {
  const urlWithBuster = bypassCache 
    ? (feedUrl.includes('?') ? `${feedUrl}&_v=${Date.now()}` : `${feedUrl}?_v=${Date.now()}`) 
    : feedUrl;

  const proxies = [
    (url: string) => `https://corsproxy.io/?${encodeURIComponent(url)}`,
    (url: string) => `https://api.allorigins.win/raw?url=${encodeURIComponent(url)}`,
    (url: string) => url
  ];

  for (const proxy of proxies) {
    try {
      const res = await fetch(proxy(urlWithBuster), bypassCache ? { cache: 'no-store' } : undefined);
      if (res.ok) {
        const text = await res.text();
        if (text && (text.includes('<rss') || text.includes('<feed') || text.includes('<xml'))) return text;
      }
    } catch (e) {
      console.warn("Proxy failed for feedUrl", feedUrl, e);
    }
  }
  return null;
};

const extractRssFromApplePodcasts = async (collectionId: number): Promise<string | null> => {
  const appleUrl = `https://podcasts.apple.com/podcast/id${collectionId}`;
  const proxies = [
    (url: string) => `https://corsproxy.io/?${encodeURIComponent(url)}`,
    (url: string) => `https://api.allorigins.win/raw?url=${encodeURIComponent(url)}`,
    (url: string) => url
  ];

  for (const proxy of proxies) {
    try {
      const res = await fetch(proxy(appleUrl));
      if (res.ok) {
        const html = await res.text();
        const match = html.match(/"feedUrl"\s*:\s*"([^"]+)"/i) ||
                      html.match(/<link[^>]+type="application\/rss\+xml"[^>]+href="([^"]+)"/i) ||
                      html.match(/href="([^"]+)"[^>]+type="application\/rss\+xml"/i);
        if (match && match[1]) {
          return match[1];
        }
      }
    } catch (e) {
      console.warn("Apple Podcast fetch failed", e);
    }
  }
  return null;
};

export const getPodcastEpisodes = async (collectionId: number, preferredCountry?: string, feedUrl?: string, bypassCache = false): Promise<Episode[]> => {
  // A. Special handler for custom audiobooks from Litterature Audio (post.id + 30000000)
  if (collectionId >= 30000000 && collectionId < 40000000) {
    try {
      const postId = collectionId - 30000000;
      const res = await fetch(`https://www.litteratureaudio.com/wp-json/wp/v2/posts/${postId}`);
      if (res.ok) {
        const postData = await res.json();
        const meta = postData.meta || {};
        
        if (meta.type === 'playlist') {
          // Extract IDs from meta.post or meta.items
          let ids: number[] = [];
          if (meta.post && typeof meta.post === 'string') {
            ids = meta.post.split(',').map(Number).filter(id => !isNaN(id) && id > 0);
          } else if (Array.isArray(meta.items)) {
            ids = meta.items.map((item: any) => {
              if (typeof item === 'string') {
                const parts = item.split(':');
                const parsedId = parseInt(parts[0], 10);
                return isNaN(parsedId) ? null : parsedId;
              }
              return null;
            }).filter((id): id is number => id !== null);
          }
          
          if (ids.length > 0) {
            const childrenRes = await fetch(`https://www.litteratureaudio.com/wp-json/wp/v2/posts?include=${ids.join(',')}&per_page=100`);
            if (childrenRes.ok) {
              const childrenData: any[] = await childrenRes.json();
              // Sort childrenData to match the exact order in 'ids'
              const orderedChildren = ids.map(id => childrenData.find((child: any) => child.id === id)).filter(Boolean);
              
              return orderedChildren.map((child: any, idx: number) => {
                const childMeta = child.meta || {};
                const streamUrl = childMeta.stream || childMeta.download_url || '';
                const duration = typeof childMeta.duration === 'number' ? childMeta.duration : 1800000;
                
                return {
                  trackId: child.id,
                  trackName: child.title.rendered.replace(/&#8211;/g, '-').replace(/&#8217;/g, "'"),
                  description: child.excerpt.rendered.replace(/<[^>]*>/g, '').replace(/&#8211;/g, '-').replace(/&#8217;/g, "'"),
                  releaseDate: child.date,
                  previewUrl: streamUrl,
                  trackTimeMillis: duration,
                  artworkUrl60: 'https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png',
                  artworkUrl160: 'https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png',
                  artworkUrl600: 'https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png',
                  collectionName: postData.title.rendered.replace(/&#8211;/g, '-').replace(/&#8217;/g, "'"),
                  collectionId: collectionId
                };
              });
            }
          }
        } else {
          // Single file post
          const streamUrl = meta.stream || meta.download_url || '';
          if (streamUrl) {
            const duration = typeof meta.duration === 'number' ? meta.duration : 1800000;
            return [{
              trackId: postData.id,
              trackName: postData.title.rendered.replace(/&#8211;/g, '-').replace(/&#8217;/g, "'"),
              description: postData.excerpt.rendered.replace(/<[^>]*>/g, '').replace(/&#8211;/g, '-').replace(/&#8217;/g, "'"),
              releaseDate: postData.date,
              previewUrl: streamUrl,
              trackTimeMillis: duration,
              artworkUrl60: 'https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png',
              artworkUrl160: 'https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png',
              artworkUrl600: 'https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png',
              collectionName: postData.title.rendered.replace(/&#8211;/g, '-').replace(/&#8217;/g, "'"),
              collectionId: collectionId
            }];
          }
        }
      }
    } catch (e) {
      console.error("Litterature Audio fetch error:", e);
    }
  }

  let resolvedFeedUrl = feedUrl;

  if (resolvedFeedUrl) {
    try {
      const xml = await fetchFeed(resolvedFeedUrl, bypassCache);
      if (xml) {
        const parsed = parseRSSFeed(xml, collectionId);
        if (parsed && parsed.length > 0) {
          return parsed;
        }
      }
    } catch (e) {
      console.warn("Direct RSS fetch failed, falling back to iTunes lookup", e);
    }
  }

  const fetchAttempt = async (countryParam?: string) => {
    try {
      let url = `${ITUNES_LOOKUP_URL}?id=${collectionId}&entity=podcastEpisode&limit=200&_v=${Date.now()}`;
      if (countryParam) url += `&country=${countryParam.toLowerCase()}`;
      
      let response = await fetch(url);
      if (!response.ok) return null;
      
      let data = await response.json();
      if (data.results && data.results.length > 0) {
        // Capture feedUrl if present
        if (data.results[0].feedUrl) {
          resolvedFeedUrl = data.results[0].feedUrl;
        }
        
        if (data.results.length > 1) {
          return data.results.slice(1).map((ep: any) => ({ ...ep, collectionId }));
        }
        
        if (data.results.length === 1 && data.results[0].wrapperType === 'audiobook') {
            const b = data.results[0];
            return [{
                trackId: b.collectionId,
                trackName: b.collectionName,
                description: b.description || b.collectionName,
                releaseDate: b.releaseDate,
                trackTimeMillis: b.trackTimeMillis || 0,
                previewUrl: b.previewUrl,
                artworkUrl60: b.artworkUrl60,
                artworkUrl160: b.artworkUrl100,
                collectionId: b.collectionId,
                collectionName: b.collectionName
            }];
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  };

  // 1. Try iTunes Lookup
  let iTunesResults: Episode[] | null = null;
  if (preferredCountry) {
    iTunesResults = await fetchAttempt(preferredCountry);
  }
  if (!iTunesResults) {
    iTunesResults = await fetchAttempt();
  }
  if (!iTunesResults && preferredCountry !== 'fr') {
    iTunesResults = await fetchAttempt('fr');
  }
  if (!iTunesResults && preferredCountry !== 'us') {
    iTunesResults = await fetchAttempt('us');
  }

  if (iTunesResults && iTunesResults.length > 0) {
    return iTunesResults;
  }

  // 2. If iTunes lookup fails or returns no episodes, fallback to RSS parsing
  let rssUrl = resolvedFeedUrl;
  const isCustomBook = collectionId >= 10000000 && collectionId < 40000000;
  if (!rssUrl && !isCustomBook) {
    // If not a custom book ID, try to get RSS feed from Apple Podcasts page
    rssUrl = await extractRssFromApplePodcasts(collectionId) || undefined;
  }

  if (rssUrl) {
    const xml = await fetchFeed(rssUrl, bypassCache);
    if (xml) {
      const parsed = parseRSSFeed(xml, collectionId);
      if (parsed.length > 0) {
        return parsed;
      }
    }
  }

  return [];
};

export const PODCAST_GENRES: Record<string, string> = {
  'News': '1489',
  'Comedy': '1303',
  'Technology': '1318',
  'Business': '1321',
  'Society & Culture': '1324',
  'True Crime': '1488',
  'Health': '1512',
  'Education': '1304',
  'History': '1487',
  'Music': '1310',
  'Science': '1533',
  'Sports': '1323'
};

const FRENCH_MARKET_TOP_IDS = [
  369369012,  // Les Grosses Têtes (RTL) - ABSOLUTE #1
  1146402624, // Hondelatte Raconte (Europe 1)
  140644703,  // L'After Foot (RMC)
  912451024,  // Affaires Sensibles (France Inter)
  357494553,  // L'heure du crime (RTL)
  1684814320, // Passé sous silence
  589182365,  // Transfert (Slate)
  1546899313  // Home(icides) (Bababam)
];

export const getTrendingPodcasts = async (country: string = 'us', category: string = 'All', bypassCache = false): Promise<Podcast[]> => {
  try {
      const genreId = category !== 'All' ? PODCAST_GENRES[category] : undefined;
      const validPodcasts: Podcast[] = [];
      const manualIds = new Set<number>();
      
      // 1. HARDCODED PREMIUM (ACPM / REAL VOLUME TOP)
      if (country === 'fr' || country === 'be') {
          const mResults = await getPodcastsByIds(FRENCH_MARKET_TOP_IDS, country);
          let mFound = mResults.filter(p => p !== null && !manualIds.has(p.collectionId));
          
          if (genreId) {
             mFound = mFound.filter(p => p.genres && p.genres.some(g => 
               g.toLowerCase().includes(category.toLowerCase()) || 
               (category === 'Comedy' && g.toLowerCase().includes('humour')) ||
               (category === 'News' && g.toLowerCase().includes('actualit'))
             ));
          }
          
          mFound.forEach(p => {
              validPodcasts.push(p);
              manualIds.add(p.collectionId);
          });
      }

      // 2. SPOTIFY TOP 200 API BRIDGE
      try {
          const spotifyUrl = `https://podcastcharts.byspotify.com/api/charts/top?region=${country}${bypassCache ? `&_v=${Date.now()}` : ''}`;
          const spotifyRes = await fetch(spotifyUrl, bypassCache ? { cache: 'no-store' } : undefined);
          if (spotifyRes.ok) {
             const spotifyData = await spotifyRes.json();
             for (let i = 0; i < 200; i += 12) {
                 const chunk = spotifyData.slice(i, i + 12);
                 if (chunk.length === 0) break;
                 
                 const results = await Promise.all(chunk.map((s: any) => matchPodcastOnItunes(s.showName, s.showPublisher || s.showName, country)));
                 let found = results.filter((p): p is Podcast => p !== null && !manualIds.has(p.collectionId));
                 
                 if (genreId) {
                     found = found.filter(p => p.genres && p.genres.some(g => 
                       g.toLowerCase().includes(category.toLowerCase()) || 
                       (category === 'Comedy' && g.toLowerCase().includes('humour')) ||
                       (category === 'News' && g.toLowerCase().includes('actualit'))
                     ));
                 }
                 
                 found.forEach(p => {
                    validPodcasts.push(p);
                    manualIds.add(p.collectionId);
                 });
                 
                 if (validPodcasts.length >= 90) break;
             }
          }
      } catch (e) {}

      // 3. APPLE RSS CHARTS (Secondary fallback)
      if (validPodcasts.length < 45) {
          let rssUrl = genreId 
            ? `https://itunes.apple.com/${country}/rss/toppodcasts/limit=150/genre=${genreId}/json`
            : `https://itunes.apple.com/${country}/rss/toppodcasts/limit=150/json`;
          if (bypassCache) {
            rssUrl += rssUrl.includes('?') ? `&_v=${Date.now()}` : `?_v=${Date.now()}`;
          }
          const rssRes = await fetch(rssUrl, bypassCache ? { cache: 'no-store' } : undefined);
          if (rssRes.ok) {
              const rssData = await rssRes.json();
              const ids = rssData?.feed?.entry?.map((e: any) => e.id.attributes['im:id']) || [];
              if (ids.length > 0) {
                  const rssPodcasts = await getPodcastsByIds(ids.map(Number), country);
                  rssPodcasts.forEach(p => {
                      if (p && !manualIds.has(p.collectionId)) {
                        validPodcasts.push(p);
                        manualIds.add(p.collectionId);
                      }
                  });
              }
          }
      }

      if (validPodcasts.length > 0) {
          if (category !== 'True Crime') {
              return validPodcasts.filter(p => {
                  const genres = p.genres?.map(g => g.toLowerCase()) || [];
                  const primaryGenre = (p.primaryGenreName || '').toLowerCase();
                  const keywords = ['true crime', 'criminology', 'criminologie', 'faits divers'];
                  return !keywords.some(kw => primaryGenre.includes(kw) || genres.some(g => g.includes(kw)));
              });
          }
          return validPodcasts;
      }
  } catch (e) {
      console.warn("Complete bridge failed, falling back to basic search...");
  }

  // 4. FINAL FALLBACK (Basic keyword search)
  try {
    const searchTerm = category === 'All' ? (country === 'fr' ? 'podcast populaire' : 'trending') : category;
    let url = `${ITUNES_SEARCH_URL}?term=${encodeURIComponent(searchTerm)}&entity=podcast&limit=150&country=${country}`;
    if (bypassCache) {
      url += `&_v=${Date.now()}`;
    }
    const response = await fetch(url, bypassCache ? { cache: 'no-store' } : undefined);
    const data = await response.json();
    const results = data.results || [];
    if (category !== 'True Crime') {
        return results.filter((p: Podcast) => {
            const genres = p.genres?.map(g => g.toLowerCase()) || [];
            const primaryGenre = (p.primaryGenreName || '').toLowerCase();
            const keywords = ['true crime', 'criminology', 'criminologie', 'faits divers'];
            return !keywords.some(kw => primaryGenre.includes(kw) || genres.some(g => g.includes(kw)));
        });
    }
    return results;
  } catch (e) {
    return [];
  }
};

export const getLibriVoxBooks = async (categoryKey: string = 'all', language: string = 'english', bypassCache = false): Promise<Podcast[]> => {
  try {
    const genreMap: Record<string, string> = {
      'fiction': 'Fiction',
      'thriller': 'Detective Fiction',
      'scifi': 'Science Fiction',
      'history': 'History',
      'kids': 'Children',
      'growth': 'Self-Help',
      'arts': 'Poetry',
    };

    const genre = genreMap[categoryKey] || '';
    let url = `https://librivox.org/api/feed/audiobooks?format=json&limit=30${genre ? `&genre=${encodeURIComponent(genre)}` : ''}&language=${language}`;
    if (bypassCache) {
      url += `&_v=${Date.now()}`;
    }
    const res = await fetch(url, bypassCache ? { cache: 'no-store' } : undefined);
    if (!res.ok) return [];
    const data = await res.json();
    
    if (!data.books) return [];

    return data.books.map((b: any) => ({
      collectionId: parseInt(b.id || '0') + 10000000, 
      artistName: b.authors ? b.authors.map((a: any) => `${a.first_name} ${a.last_name}`).join(', ') : 'LibriVox',
      collectionName: b.title,
      artworkUrl100: 'https://librivox.org/images/librivox-logo.png',
      artworkUrl600: 'https://librivox.org/images/librivox-logo.png',
      feedUrl: b.url_rss,
      genres: [b.genre || 'Audiobook'],
      primaryGenreName: 'Audiobook',
      releaseDate: b.copyright_year || 'Unknown',
      source: 'librivox',
      description: b.description
    }));
  } catch (e) {
    return [];
  }
};

export const getInternetArchiveBooks = async (categoryKey: string = 'all', lang: string = 'en', bypassCache = false): Promise<Podcast[]> => {
  try {
     const language = lang === 'fr' ? 'french' : 'english';
     const genreMap: Record<string, string> = {
        'fiction': 'classics',
        'thriller': 'mystery',
        'scifi': 'science fiction',
        'history': 'history',
        'kids': 'children',
        'growth': 'spirituality',
        'arts': 'arts'
     };
     const genreTerm = genreMap[categoryKey] ? ` AND ${genreMap[categoryKey]}` : '';
     let url = `https://archive.org/advancedsearch.php?q=mediatype%3Aaudio+AND+collection%3A%28audio_bookspoetry%29+AND+language%3A${language}${genreTerm}&fl[]=identifier,title,creator,date,description,downloads&sort[]=downloads+desc&rows=30&output=json`;
     if (bypassCache) {
       url += `&_v=${Date.now()}`;
     }
     const res = await fetch(url, bypassCache ? { cache: 'no-store' } : undefined);
     const data = await res.json();
     if (!data.response?.docs) return [];
     
     return data.response.docs.map((d: any) => ({
       collectionId: d.identifier.split('').reduce((acc: number, char: string) => acc + char.charCodeAt(0), 0) + 20000000, 
       artistName: d.creator || 'Internet Archive',
       collectionName: d.title,
       artworkUrl100: `https://archive.org/services/img/${d.identifier}`,
       artworkUrl600: `https://archive.org/services/img/${d.identifier}`,
       feedUrl: `https://archive.org/services/rss.php?query=identifier%3A${d.identifier}`,
       genres: ['Audiobook'],
       primaryGenreName: 'Audiobook',
       releaseDate: d.date || 'Unknown',
       source: 'archive',
       description: d.description
     }));
  } catch(e) { return []; }
};

export const getStorynoryBooks = async (): Promise<Podcast[]> => {
  try {
    // RSS for Storynory
    const url = 'https://www.storynory.com/feed/podcast/';
    // Storynory is best handled by iTunes Search but let's provide a direct access if needed
    // For now we use the search specifically for them
    const res = await fetch(`${ITUNES_SEARCH_URL}?term=Storynory&entity=podcast&limit=10`);
    const data = await res.json();
    return (data.results || []).map((p: any) => ({ ...p, source: 'storynory' }));
  } catch(e) { return []; }
};

export const getLitteratureAudioBooks = async (bypassCache = false): Promise<Podcast[]> => {
  try {
    let url = 'https://www.litteratureaudio.com/wp-json/wp/v2/posts?per_page=20';
    if (bypassCache) {
      url += `&_v=${Date.now()}`;
    }
    const res = await fetch(url, bypassCache ? { cache: 'no-store' } : undefined);
    const data = await res.json();
    return data.map((post: any) => ({
       collectionId: post.id + 30000000,
       artistName: 'Litterature Audio',
       collectionName: post.title.rendered.replace(/&#8211;/g, '-').replace(/&#8217;/g, "'"),
       artworkUrl100: 'https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png',
       artworkUrl600: 'https://www.litteratureaudio.com/wp-content/themes/litteratureaudio/images/logo.png',
       feedUrl: `${post.link}feed/`,
       genres: ['Livre Audio'],
       primaryGenreName: 'Audiobook',
       releaseDate: post.date,
       source: 'litteratureaudio',
       description: post.excerpt.rendered.replace(/<[^>]*>/g, '')
    }));
  } catch(e) { return []; }
};

export const categorizePodcast = (p: Partial<Podcast>): string => {
  const text = `${p.collectionName} ${p.artistName} ${p.description} ${p.genres?.join(' ')}`.toLowerCase();
  
  if (text.match(/enfant|jeunesse|kids|children|storynory|conte|fable/)) return 'kids';
  if (text.match(/policier|crime|thriller|detective|mystery|meurtre|enquête/)) return 'thriller';
  if (text.match(/science fiction|fantasy|imaginaire|scifi|fantastique|cosmos|futur|robot/)) return 'scifi';
  if (text.match(/histoire|biographie|history|biography|mémoires|war|guerre|siècle/)) return 'history';
  if (text.match(/développement|personnel|self help|spirituality|spiritualité|méditation|yoga|santé|health/)) return 'growth';
  if (text.match(/philosophie|philosophy|société|society|politics|politique|économie/)) return 'arts'; // Consolidated
  if (text.match(/art|design|peinture|musique|music|poésie|poetry|théâtre|drama|culture/)) return 'arts';
  
  return 'fiction'; // Default
};

export const getAudiobooks = async (country: string = 'us', categoryKey: string = 'all', bypassCache = false): Promise<Podcast[]> => {
  const allResults: Podcast[] = [];
  const seenIds = new Set<number>();
  const seenTitles = new Set<string>();

  try {
      if (categoryKey === 'all') {
          let rssUrl = `https://itunes.apple.com/${country}/rss/topaudiobooks/limit=25/json`;
          if (bypassCache) {
            rssUrl += rssUrl.includes('?') ? `&_v=${Date.now()}` : `?_v=${Date.now()}`;
          }
          const rssRes = await fetch(rssUrl, bypassCache ? { cache: 'no-store' } : undefined);
          if (rssRes.ok) {
             const rssData = await rssRes.json();
             if (rssData?.feed?.entry) {
                 const ids: string[] = rssData.feed.entry.map((e: any) => e.id.attributes['im:id']);
                 const url = `${ITUNES_LOOKUP_URL}?id=${ids.join(',')}&country=${country}&_v=${Date.now()}`;
                 const lookupRes = await fetch(url);
                 const lookupData = await lookupRes.json();
                 
                 if (lookupData.results) {
                     const books: Podcast[] = lookupData.results;
                     books.sort((a, b) => ids.indexOf(a.collectionId.toString()) - ids.indexOf(b.collectionId.toString()));
                     books.forEach(b => { 
                        seenIds.add(b.collectionId); 
                        seenTitles.add(b.collectionName.toLowerCase());
                        allResults.push({ ...b, source: 'itunes' }); 
                     });
                 }
             }
          }
      }

      const categoryTerms: Record<string, string> = {
        'fiction': country === 'fr' ? 'Romans Classiques Livre Audio' : 'Fiction Classics Audiobook',
        'thriller': country === 'fr' ? 'Policier Thriller Livre Audio' : 'Mystery Thriller Audiobook',
        'scifi': country === 'fr' ? 'Science Fiction Fantasy Livre Audio' : 'Sci-Fi Fantasy Audiobook',
        'history': country === 'fr' ? 'Histoire Biographie Livre Audio' : 'History Biography Audiobook',
        'kids': country === 'fr' ? 'Enfants Jeunesse Livre Audio' : 'Kids Teens Audiobook',
        'growth': country === 'fr' ? 'Développement Spiritualité Livre Audio' : 'Self Help Spiritual Audiobook',
        'arts': country === 'fr' ? 'Arts Philosophie Poésie Théâtre' : 'Arts Philosophy Poetry Drama',
        'all': country === 'fr' ? 'Livre Audio' : 'Audiobook'
      };

      const mainTerm = categoryTerms[categoryKey] || 'Audiobook';
      let url = `${ITUNES_SEARCH_URL}?term=${encodeURIComponent(mainTerm)}&entity=podcast&limit=40&country=${country}`;
      if (bypassCache) {
        url += `&_v=${Date.now()}`;
      }
      const res = await fetch(url, bypassCache ? { cache: 'no-store' } : undefined);
      const data = await res.json();
      
      if (data.results) {
          data.results.forEach((p: Podcast) => {
              if (!seenIds.has(p.collectionId) && !seenTitles.has(p.collectionName.toLowerCase())) {
                  seenIds.add(p.collectionId);
                  seenTitles.add(p.collectionName.toLowerCase());
                  allResults.push({ ...p, source: 'itunes' });
              }
          });
      }

      // Add LibriVox results
      const librivoxBooks = await getLibriVoxBooks(categoryKey, country === 'fr' ? 'french' : 'english', bypassCache);
      librivoxBooks.forEach(b => {
          const title = b.collectionName.toLowerCase();
          if (!seenIds.has(b.collectionId) && !seenTitles.has(title)) {
              seenIds.add(b.collectionId);
              seenTitles.add(title);
              allResults.push(b);
          }
      });

      // Add Internet Archive results
      const archiveBooks = await getInternetArchiveBooks(categoryKey, country === 'fr' ? 'fr' : 'en', bypassCache);
      archiveBooks.forEach(b => {
          const title = b.collectionName.toLowerCase();
          if (!seenIds.has(b.collectionId) && !seenTitles.has(title)) {
              seenIds.add(b.collectionId);
              seenTitles.add(title);
              allResults.push(b);
          }
      });

      // Special source for Kids in English
      if (categoryKey === 'kids' || categoryKey === 'all') {
          const storynory = await getStorynoryBooks();
          storynory.forEach(b => {
             if (!seenIds.has(b.collectionId)) {
                seenIds.add(b.collectionId);
                allResults.push(b);
             }
          });
      }

      // French Specific Source
      if (country === 'fr' && (categoryKey === 'all' || categoryKey === 'fiction')) {
          const la = await getLitteratureAudioBooks(bypassCache);
          la.forEach(b => {
             if (!seenIds.has(b.collectionId)) {
                seenIds.add(b.collectionId);
                allResults.push(b);
             }
          });
      }

  } catch(e) {}

  return allResults;
};


export const getRadioStations = async (radioSearch: string, langCode: string, bypassCache = false): Promise<RadioStation[]> => {
  try {
    let url = `${RADIO_API_BASE}/bylanguage/${encodeURIComponent(radioSearch)}?limit=300&order=clickcount&reverse=true`;
    if (bypassCache) {
      url += `&_v=${Date.now()}`;
    }
    const response = await fetch(url, bypassCache ? { cache: 'no-store' } : undefined);
    const data = await response.json();
    const formatted = data.map((station: any) => ({
      id: station.stationuuid,
      name: station.name,
      url: station.url_resolved,
      favicon: station.favicon || `https://api.dicebear.com/9.x/shapes/svg?seed=${encodeURIComponent(station.name)}`,
      tags: station.tags,
      country: station.country,
      clickcount: station.clickcount
    }));
    return sortStations(formatted, langCode);
  } catch (error) { return []; }
};

export const searchAll = async (term: string, country: string = 'us', langCode: string = 'en'): Promise<UnifiedSearchResults> => {
  let langParam = '';
  if (country === 'fr') langParam = '&lang=fr_FR';
  
  const podUrl = `${ITUNES_SEARCH_URL}?term=${encodeURIComponent(term)}&entity=podcast&limit=40&country=${country}${langParam}&_v=${Date.now()}`;
  const epUrl = `${ITUNES_SEARCH_URL}?term=${encodeURIComponent(term)}&entity=podcastEpisode&limit=20&country=${country}${langParam}&_v=${Date.now()}`;
  const radUrl = `${RADIO_API_BASE}/byname/${encodeURIComponent(term)}?limit=50&order=clickcount&reverse=true`;
  const [pRes, eRes, rRes] = await Promise.all([fetch(podUrl), fetch(epUrl), fetch(radUrl)]);
  const pData = await pRes.json();
  const eData = await eRes.json();
  const rData = await rRes.json();
  return {
    podcasts: pData.results || [],
    episodes: eData.results || [],
    radio: sortStations(rData.map((s: any) => ({
      id: s.stationuuid,
      name: s.name,
      url: s.url_resolved,
      favicon: s.favicon || `https://api.dicebear.com/9.x/shapes/svg?seed=${encodeURIComponent(s.name)}`,
      tags: s.tags,
      country: s.country,
      clickcount: s.clickcount
    })), langCode)
  };
};
