
import React, { useEffect, useState, useMemo } from 'react';
import { getPodcastEpisodes } from '../services/api';
import { saveOfflineEpisode, deleteOfflineEpisode, getAllOfflineIds } from '../services/offline';
import { Episode, LangCode, Podcast, AccentColor } from '../types';
import { translations } from '../translations';

interface EpisodesViewProps {
  followedPodcasts: Podcast[];
  langCode: LangCode;
  onPlayEpisode: (episode: Episode) => void;
  onAddToQueue: (episode: Episode, next?: boolean) => void;
  accentColor: AccentColor;
  playedEpisodeIds: number[];
  longestPerDayOnly?: boolean;
  settings: AppSettings;
}

const EpisodesView: React.FC<EpisodesViewProps> = ({ followedPodcasts, langCode, onPlayEpisode, onAddToQueue, accentColor, playedEpisodeIds, longestPerDayOnly = false, settings }) => {
  const [episodes, setEpisodes] = useState<Episode[]>(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('podcast_ultra_cached_episodes');
      return saved ? JSON.parse(saved) : [];
    }
    return [];
  });
  const [loading, setLoading] = useState(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('podcast_ultra_cached_episodes');
      const parsed = saved ? JSON.parse(saved) : [];
      return parsed.length === 0;
    }
    return true;
  });

  const [alertMessage, setAlertMessage] = useState("");
  const [showAlert, setShowAlert] = useState(false);

  const [filterType, setFilterType] = useState<'all' | 'unplayed' | 'downloaded'>('all');
  const [dismissedIds, setDismissedIds] = useState<number[]>(() => {
    const saved = localStorage.getItem('podcast_ultra_dismissed');
    return saved ? JSON.parse(saved) : [];
  });
  const [downloadedIds, setDownloadedIds] = useState<number[]>([]);
  const [downloadingIds, setDownloadingIds] = useState<number[]>([]);
  const [weather, setWeather] = useState<{ temperature: number; weathercode: number; cityName: string } | null>(null);
  const [refreshKey, setRefreshKey] = useState(0);

  const t = translations[langCode];

  const shouldRefreshCache = (): boolean => {
    const lastFetch = localStorage.getItem('podcast_ultra_episodes_last_fetch');
    if (!lastFetch) return true;
    const elapsed = Date.now() - new Date(lastFetch).getTime();
    return elapsed > 24 * 60 * 60 * 1000; // 24 hours
  };

  useEffect(() => {
    if (loading && episodes.length === 0) {
      navigator.geolocation.getCurrentPosition(
        async (position) => {
          const { latitude, longitude } = position.coords;
          try {
            const res = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=${latitude}&longitude=${longitude}&current_weather=true`);
            const data = await res.json();

            let city = "Ma Position";
            try {
              const geoRes = await fetch(`https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${latitude}&longitude=${longitude}&localityLanguage=${langCode}`);
              const geoData = await geoRes.json();
              if (geoData.city || geoData.locality) {
                city = geoData.city || geoData.locality;
              }
            } catch (e) { }

            setWeather({
              temperature: data.current_weather.temperature,
              weathercode: data.current_weather.weathercode,
              cityName: city
            });
          } catch (e) {
            console.error(e);
          }
        },
        async (error) => {
          try {
            const res = await fetch(`https://api.open-meteo.com/v1/forecast?latitude=48.8566&longitude=2.3522&current_weather=true`);
            const data = await res.json();
            setWeather({
              temperature: data.current_weather.temperature,
              weathercode: data.current_weather.weathercode,
              cityName: "Paris (Défaut)"
            });
          } catch (e) {
            console.error(e);
          }
        }
      );
    }
  }, [loading, episodes.length]);

  const getWeatherDetails = (code: number) => {
    switch (code) {
      case 0: return { desc: "Ciel dégagé", icon: "fa-sun text-amber-400" };
      case 1:
      case 2:
      case 3: return { desc: "Partiellement nuageux", icon: "fa-cloud-sun text-blue-300" };
      case 45:
      case 48: return { desc: "Brouillard", icon: "fa-smog text-slate-400" };
      case 51:
      case 53:
      case 55: return { desc: "Bruine", icon: "fa-cloud-rain text-blue-400" };
      case 61:
      case 63:
      case 65: return { desc: "Pluie", icon: "fa-cloud-showers-heavy text-blue-500" };
      case 71:
      case 73:
      case 75: return { desc: "Neige", icon: "fa-snowflake text-sky-200" };
      case 80:
      case 81:
      case 82: return { desc: "Averses", icon: "fa-cloud-showers-heavy text-blue-600" };
      case 95:
      case 96:
      case 99: return { desc: "Orage", icon: "fa-cloud-bolt text-yellow-500" };
      default: return { desc: "Nuageux", icon: "fa-cloud text-slate-300" };
    }
  };

  useEffect(() => {
    localStorage.setItem('podcast_ultra_dismissed', JSON.stringify(dismissedIds));
  }, [dismissedIds]);

  // Load downloaded IDs on mount
  useEffect(() => {
    getAllOfflineIds().then(setDownloadedIds);
  }, []);

  useEffect(() => {
    if (!followedPodcasts || followedPodcasts.length === 0) {
      setLoading(false);
      setEpisodes([]);
      return;
    }

    // Skip fetch if cache is fresh and not a forced refresh
    if (refreshKey === 0 && episodes.length > 0 && !shouldRefreshCache()) {
      return;
    }

    const loadEpisodes = async () => {
      setLoading(true);
      const allEpisodes: Episode[] = [];

      // Filter out audiobooks from the feed
      const validPodcasts = followedPodcasts.filter(p => {
        const isAudiobook = p.genres?.some(g => {
          const genre = g.toLowerCase();
          return genre.includes('audiobook') || genre.includes('fiction') || genre.includes('book') || genre.includes('livre');
        });
        return !isAudiobook;
      });

      const results = await Promise.all(
        validPodcasts.map(async (podcast) => {
          try {
            return await getPodcastEpisodes(podcast.collectionId, podcast.country, podcast.feedUrl, refreshKey > 0);
          } catch (e) {
            return [];
          }
        })
      );
      results.forEach(res => { if (res) allEpisodes.push(...res); });

      let processed = allEpisodes;
      if (longestPerDayOnly) {
        const groups = new Map<string, Episode>();
        processed.forEach(ep => {
          if (!ep.releaseDate || !ep.collectionId) return;
          const localDate = new Date(ep.releaseDate);
          const dateStr = `${localDate.getFullYear()}-${String(localDate.getMonth() + 1).padStart(2, '0')}-${String(localDate.getDate()).padStart(2, '0')}`;
          const key = `${ep.collectionId}-${dateStr}`;
          const current = groups.get(key);
          const currentLen = current?.trackTimeMillis || 0;
          const newLen = ep.trackTimeMillis || 0;
          if (!current || newLen > currentLen) {
            groups.set(key, ep);
          }
        });
        processed = Array.from(groups.values());
      }

      processed.sort((a, b) => new Date(b.releaseDate).getTime() - new Date(a.releaseDate).getTime());
      
      // Filter episodes up to 1 week (7 days)
      const oneWeekAgo = new Date();
      oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);
      const withinOneWeek = processed.filter(ep => {
        if (!ep.releaseDate) return false;
        const releaseDate = new Date(ep.releaseDate);
        return releaseDate >= oneWeekAgo;
      });

      setEpisodes(withinOneWeek);
      if (typeof window !== 'undefined') {
        localStorage.setItem('podcast_ultra_cached_episodes', JSON.stringify(withinOneWeek));
        localStorage.setItem('podcast_ultra_episodes_last_fetch', new Date().toISOString());
      }
      setLoading(false);
    };

    loadEpisodes();
  }, [followedPodcasts, refreshKey]);

  const handleDownload = async (episode: Episode, e: React.MouseEvent) => {
    e.stopPropagation();
    if (downloadingIds.includes(episode.trackId)) return;

    if (downloadedIds.includes(episode.trackId)) {
      await deleteOfflineEpisode(episode.trackId);
      setDownloadedIds(prev => prev.filter(i => i !== episode.trackId));
      return;
    }

    setDownloadingIds(prev => [...prev, episode.trackId]);
    try {
      const response = await fetch(episode.previewUrl);
      await saveOfflineEpisode(episode.trackId, await response.blob());
      setDownloadedIds(prev => [...prev, episode.trackId]);
    } catch (e) {
      console.error("Download failed", e);
    } finally {
      setDownloadingIds(prev => prev.filter(i => i !== episode.trackId));
    }
  };

  const filteredEpisodes = useMemo(() => {
    let result = episodes;

    // Filtre d'épisode unique le plus long par jour par podcast
    if (longestPerDayOnly) {
      const groups = new Map<string, Episode>();
      result.forEach(ep => {
        if (!ep.releaseDate || !ep.collectionId) return;
        const localDate = new Date(ep.releaseDate);
        const dateStr = `${localDate.getFullYear()}-${String(localDate.getMonth() + 1).padStart(2, '0')}-${String(localDate.getDate()).padStart(2, '0')}`;
        const key = `${ep.collectionId}-${dateStr}`;
        const current = groups.get(key);
        const currentLen = current?.trackTimeMillis || 0;
        const newLen = ep.trackTimeMillis || 0;
        if (!current || newLen > currentLen) {
          groups.set(key, ep);
        }
      });
      result = Array.from(groups.values()).sort((a, b) => new Date(b.releaseDate).getTime() - new Date(a.releaseDate).getTime());
    }

    const filtered = result.filter(ep => {
      const isDismissed = dismissedIds.includes(ep.trackId);
      if (isDismissed) return false;

      // Filter Logic (Really hide played ones)
      if (filterType === 'unplayed' && playedEpisodeIds.includes(ep.trackId)) return false;
      if (filterType === 'downloaded' && !downloadedIds.includes(ep.trackId)) return false;

      return true;
    });

    return filtered;
  }, [episodes, dismissedIds, longestPerDayOnly, filterType, playedEpisodeIds, downloadedIds]);

  const handleDismiss = (id: number) => setDismissedIds(prev => [...prev, id]);



  if (loading && episodes.length === 0) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center h-full px-6 text-center">
        <div className="relative mb-6">
          <div className={`animate-spin w-14 h-14 border-[3px] border-${accentColor}-500/20 border-t-${accentColor}-500 rounded-full`}></div>
          <div className="absolute inset-0 flex items-center justify-center">
            <i className={`fa-solid fa-cloud-sun text-${accentColor}-400 text-sm`}></i>
          </div>
        </div>
        <h2 className="text-white font-black text-xl mb-2">Synchronisation</h2>
        <p className="text-slate-500 text-sm max-w-[240px] leading-relaxed mb-8">Nous récupérons les derniers épisodes de vos podcasts favoris...</p>

        {weather && (
          <div className="bg-slate-900/60 border border-white/5 rounded-3xl p-5 shadow-2xl backdrop-blur-md max-w-xs w-full mx-auto transition-all hover:border-white/10">
            <span className="text-[10px] font-black text-indigo-400 tracking-[0.2em] uppercase block mb-3 text-center">Météo Locale</span>
            <div className="flex items-center gap-4">
              <div className="w-12 h-12 rounded-2xl bg-white/5 flex items-center justify-center flex-shrink-0">
                <i className={`fa-solid ${getWeatherDetails(weather.weathercode).icon} text-2xl`}></i>
              </div>
              <div className="text-left min-w-0">
                <h3 className="text-white font-bold text-sm truncate leading-tight">{weather.cityName}</h3>
                <p className="text-slate-400 text-xs truncate mt-0.5">{getWeatherDetails(weather.weathercode).desc}</p>
              </div>
              <div className="text-white text-2xl font-black ml-auto flex-shrink-0">
                {Math.round(weather.temperature)}°C
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="w-full max-w-5xl mx-auto px-4 sm:px-6 md:px-8 py-6 md:py-10 pb-40">

      {showAlert && alertMessage && (
        <div className="fixed top-20 right-8 z-50 bg-emerald-500 text-white px-6 py-3 rounded-2xl shadow-xl animate-in slide-in-from-top-4 font-bold text-sm">
          {alertMessage}
        </div>
      )}

      {/* Header Section */}
      <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-6 mb-8">
        <button
          onClick={() => setRefreshKey(k => k + 1)}
          title={langCode === 'fr' ? 'Rafraîchir les épisodes' : 'Refresh episodes'}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-bold bg-slate-900 border border-white/5 text-slate-400 hover:text-white hover:border-${accentColor}-500/30 transition-all`}
        >
          <i className={`fa-solid fa-arrows-rotate ${loading ? 'animate-spin' : ''}`}></i>
          <span className="hidden sm:inline">{langCode === 'fr' ? 'Rafraîchir' : 'Refresh'}</span>
        </button>
        <div className="flex gap-2 flex-wrap">
          <div className="flex bg-slate-900 border border-white/5 p-1 rounded-2xl">
            <button
              onClick={() => setFilterType('all')}
              className={`px-3 sm:px-4 py-2.5 rounded-xl text-[10px] sm:text-xs font-bold uppercase tracking-wide transition-all ${filterType === 'all' ? `bg-${accentColor}-600 text-white shadow-lg` : 'dark:text-slate-400 text-slate-500 hover:text-white'}`}
            >
              {t.filter_all}
            </button>
            <button
              onClick={() => setFilterType('unplayed')}
              className={`px-3 sm:px-4 py-2.5 rounded-xl text-[10px] sm:text-xs font-bold uppercase tracking-wide transition-all ${filterType === 'unplayed' ? `bg-${accentColor}-600 text-white shadow-lg` : 'dark:text-slate-400 text-slate-500 hover:text-white'}`}
            >
              {t.filter_unplayed}
            </button>
            <button
              onClick={() => setFilterType('downloaded')}
              className={`px-3 sm:px-4 py-2.5 rounded-xl text-[10px] sm:text-xs font-bold uppercase tracking-wide transition-all ${filterType === 'downloaded' ? `bg-${accentColor}-600 text-white shadow-lg` : 'dark:text-slate-400 text-slate-500 hover:text-white'}`}
            >
              {t.filter_downloaded}
            </button>
          </div>
        </div>
      </div>

      {/* Episodes List */}
      {followedPodcasts.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-24 text-center text-slate-500 px-6">
          <div className="w-24 h-24 bg-slate-900 rounded-[2.5rem] flex items-center justify-center mb-8 text-slate-800 text-5xl border border-white/5 shadow-inner"><i className="fa-solid fa-rss"></i></div>
          <h2 className="text-xl font-black text-white mb-3">Votre flux est vide</h2>
          <p className="max-w-xs text-sm font-medium leading-relaxed opacity-60">Ajoutez des podcasts en favoris pour centraliser tous leurs épisodes ici.</p>
        </div>
      ) : filteredEpisodes.length === 0 && !loading ? (
        <div className="flex flex-col items-center justify-center py-24 text-center text-slate-500 px-6">
          <div className="w-20 h-20 bg-slate-900 rounded-full flex items-center justify-center mb-8 border border-white/5"><i className="fa-solid fa-filter-circle-xmark text-4xl opacity-20"></i></div>
          <h2 className="text-xl font-black text-white mb-2">Aucun résultat</h2>
          <p className="max-w-xs text-sm font-medium opacity-60">Ajustez votre recherche ou vos filtres pour voir plus d'épisodes.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4">
          {filteredEpisodes.map((ep, idx) => (
            // Episode item with swipe actions (right: download, left: hide) and add-to-playlist button only
            <div
              key={`${ep.trackId}-${idx}`}
              className={`group relative bg-slate-900/40 p-3.5 sm:p-5 rounded-[1.8rem] md:rounded-[2.5rem] border border-white/5 hover:bg-slate-800/80 hover:border-${accentColor}-500/40 transition-all flex flex-row items-center gap-4 sm:gap-6 shadow-xl overflow-hidden ${playedEpisodeIds.includes(ep.trackId) ? 'opacity-60 grayscale hover:opacity-100 hover:grayscale-0' : ''}`}
              onTouchStart={e => { e.currentTarget.dataset.startX = e.touches[0].clientX; }}
              onTouchEnd={e => {
                const startX = Number(e.currentTarget.dataset.startX);
                const endX = e.changedTouches[0].clientX;
                const diff = endX - startX;
                if (diff > 80) {
                  // Swipe right → download
                  handleDownload(ep, e);
                } else if (diff < -80) {
                  // Swipe left → hide
                  handleDismiss(ep.trackId);
                }
              }}
            >
              <div className="relative flex-shrink-0 cursor-pointer" onClick={() => onPlayEpisode(ep)}>
                <img 
                  src={ep.artworkUrl160 || ep.artworkUrl60 || ep.artworkUrl600 || followedPodcasts.find(p => p.collectionId === ep.collectionId)?.artworkUrl600 || followedPodcasts.find(p => p.collectionId === ep.collectionId)?.artworkUrl100 || ''} 
                  className="w-16 h-16 sm:w-20 sm:h-20 lg:w-24 lg:h-24 rounded-2xl sm:rounded-3xl object-cover shadow-2xl transition-transform duration-500 group-hover:scale-105" 
                />
                <div className="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                  <i className="fa-solid fa-play text-white text-lg drop-shadow-[0_2px_6px_rgba(0,0,0,0.8)]" />
                </div>
              </div>

              <div className="flex-1 min-w-0 py-1">
                <div className="flex items-center justify-between mb-1.5">
                  {ep.collectionName && !ep.trackName.toLowerCase().includes(ep.collectionName.toLowerCase()) ? (
                    <p className={`text-[9px] sm:text-[10px] font-black text-${accentColor}-400 uppercase tracking-widest truncate max-w-[70%]`}>{ep.collectionName}</p>
                  ) : (
                    <div className="flex-1" />
                  )}
                  <span className="text-[9px] sm:text-[10px] font-black text-slate-600 bg-black/20 px-2 py-0.5 rounded-md whitespace-nowrap ml-2">
                    {(() => {
                      const date = new Date(ep.releaseDate);
                      const datePart = date.toLocaleDateString(langCode === 'fr' ? 'fr-FR' : 'en-US', { day: 'numeric', month: 'short' });
                      const timePart = date.toLocaleTimeString(langCode === 'fr' ? 'fr-FR' : 'en-US', { hour: '2-digit', minute: '2-digit' });
                      return langCode === 'fr' ? `${datePart} à ${timePart}` : `${datePart}, ${timePart}`;
                    })()}
                  </span>
                </div>
                {ep.trackName.length > 35 ? (
                  <div className="marquee-container mb-2 sm:mb-3">
                    <div className="animate-marquee">
                      <h3 className={`font-bold text-white text-sm sm:text-base lg:text-xl leading-tight hover:text-${accentColor}-300 transition-colors cursor-pointer inline-block`} onClick={() => onPlayEpisode(ep)}>
                        {ep.trackName}
                        <span className="px-6 opacity-0">---</span>
                        {ep.trackName}
                        <span className="px-6 opacity-0">---</span>
                      </h3>
                    </div>
                  </div>
                ) : (
                  <h3 className={`font-bold text-white text-sm sm:text-base lg:text-xl mb-2 sm:mb-3 leading-tight hover:text-${accentColor}-300 transition-colors cursor-pointer`} onClick={() => onPlayEpisode(ep)}>
                    {ep.trackName}
                  </h3>
                )}
                <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-[9px] sm:text-[10px] text-slate-500 font-black uppercase tracking-wider">
                  <span className="flex items-center gap-1.5"><i className={`fa-regular fa-clock text-${accentColor}-500/60 text-xs`} />{ep.trackTimeMillis ? `${Math.floor(ep.trackTimeMillis / 60000)}m` : 'N/A'}</span>
                  {playedEpisodeIds.includes(ep.trackId) && (
                    <span className="text-emerald-500 flex items-center gap-1.5"><i className="fa-solid fa-check" /> LU</span>
                  )}
                  {downloadedIds.includes(ep.trackId) && (
                    <span className="text-emerald-400 flex items-center gap-1.5"><i className="fa-solid fa-download" /> DL</span>
                  )}
                </div>
              </div>

              <div className="flex flex-col sm:flex-row items-center gap-2 flex-shrink-0">
                {/* Add to queue button */}
                <button
                  onClick={() => {
                    onAddToQueue(ep);
                    setAlertMessage(`"${ep.trackName}" ajouté à la liste de lecture`);
                    setShowAlert(true);
                    setTimeout(() => setShowAlert(false), 3000);
                  }}
                  className={`w-10 h-10 sm:w-12 sm:h-12 rounded-full bg-slate-800/80 hover:bg-${accentColor}-600 dark:text-slate-400 text-slate-500 hover:text-white flex items-center justify-center transition-all shadow-xl hover:scale-110 active:scale-90`}
                  title="Ajouter à la liste de lecture"
                >
                  <i className="fa-solid fa-plus text-xs sm:text-sm" />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default EpisodesView;
