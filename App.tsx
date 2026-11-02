
import React, { useState, useEffect, useRef, useMemo } from 'react';
import { HashRouter as Router, Routes, Route, useNavigate, useLocation, Link } from 'react-router-dom';
import Sidebar from './components/Sidebar';
import Player from './components/Player';
import DiscoverView from './components/DiscoverView';
import PodcastDetailView from './components/PodcastDetailView';
import RadioView from './components/RadioView';
import AudiobooksView from './components/AudiobooksView';
import EpisodesView from './components/EpisodesView';
import RecentEpisodesView from './components/RecentEpisodesView';
import SettingsView from './components/SettingsView';
import LibraryView from './components/LibraryView';
import SearchView from './components/SearchView';
import { getOfflineEpisode, deleteOfflineEpisode } from './services/offline';
import { getPodcastEpisodes } from './services/api';
import { Podcast, Episode, RadioStation, PlaybackState, Playlist, LANGUAGES, LangCode, User, AppSettings, AccentColor } from './types';
import { translations } from './translations';

function BottomNav({ currentPath, lang, accentColor, playback }: { currentPath: string, lang: LangCode, accentColor: AccentColor, playback: PlaybackState }) {
  const t = translations[lang];
  
  const links = [
    { icon: 'fa-compass', path: '/', label: t.discover },
    { icon: 'fa-clapperboard', path: '/episodes', label: t.episodes_feed },
    { icon: 'player', path: '/player', label: '' }, 
    { icon: 'fa-book-open', path: '/audiobooks', label: t.audiobooks },
    { icon: 'fa-radio', path: '/radio', label: t.radio || 'Radio' },
  ];

  return (
    <nav className="lg:hidden fixed bottom-0 left-0 right-0 h-20 bg-slate-950/90 backdrop-blur-3xl border-t border-white/5 flex items-end justify-between z-[60] px-2 pb-safe shadow-[0_-10px_30px_rgba(0,0,0,0.5)]">
      {links.map((link) => {
        const isPlayer = link.icon === 'player';
        const isActive = currentPath === link.path;
        
        if (isPlayer) {
            return (
                <Link 
                  key={link.path} 
                  to={link.path} 
                  className="flex flex-col items-center justify-end h-full w-1/5 pb-3 group relative"
                >
                  <div className={`w-14 h-14 rounded-full flex items-center justify-center transition-all duration-300 shadow-xl ${isActive ? `bg-${accentColor}-500 text-white scale-110 border-4 border-slate-950` : `bg-slate-800 dark:text-slate-400 text-slate-500 border border-white/10 group-hover:bg-slate-700`}`}>
                    {playback.isPlaying ? (
                        <div className="flex gap-1 items-end h-4">
                            <span className="w-1 bg-white rounded-full animate-[bounce_1s_infinite] h-3"></span>
                            <span className="w-1 bg-white rounded-full animate-[bounce_1.2s_infinite] h-5"></span>
                            <span className="w-1 bg-white rounded-full animate-[bounce_0.8s_infinite] h-3"></span>
                        </div>
                    ) : (
                        <i className={`fa-solid fa-play text-xl ml-1`}></i>
                    )}
                  </div>
                </Link>
            );
        }

        return (
            <Link 
              key={link.path} 
              to={link.path} 
              className={`flex flex-col items-center justify-center gap-1.5 transition-all duration-300 w-1/5 h-16 mb-2 ${isActive ? `text-${accentColor}-400` : 'text-slate-500 hover:text-slate-300'}`}
            >
              <div className={`w-8 h-8 rounded-xl flex items-center justify-center transition-all ${isActive ? `bg-${accentColor}-500/10` : ''}`}>
                <i className={`fa-solid ${link.icon} text-lg`}></i>
              </div>
              <span className="text-[10px] font-bold tracking-tight leading-none w-full text-center whitespace-nowrap overflow-visible">{link.label}</span>
            </Link>
        );
      })}
    </nav>
  );
}

function AppContent() {
  const [user, setUser] = useState<User | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [settings, setSettings] = useState<AppSettings>({ playbackSpeed: 1, skipIntro: true, accentColor: 'indigo', theme: 'dark', longestPerDayOnly: true });
  const [playback, setPlayback] = useState<PlaybackState>({ currentTrack: null, isPlaying: false, type: 'podcast', queue: [], speed: 1 });
  const [favorites, setFavorites] = useState<Podcast[]>([]); 
  const [favoriteRadios, setFavoriteRadios] = useState<string[]>([]);
  const [language, setLanguage] = useState(LANGUAGES.find(l => l.code === 'fr') || LANGUAGES[0]);
  const [playedEpisodeIds, setPlayedEpisodeIds] = useState<number[]>([]);
  const [savedPositions, setSavedPositions] = useState<Record<string, number>>({});
  // Nouvelle variable d'état pour l'historique complet
  const [history, setHistory] = useState<Episode[]>([]);

  const audioRef = useRef<HTMLAudioElement | null>(null);
  const objectUrlRef = useRef<string | null>(null);

  const navigate = useNavigate();
  const location = useLocation();
  const t = translations[language.code as LangCode];

  // Sync playback speed
  useEffect(() => {
     if (audioRef.current) {
         audioRef.current.playbackRate = settings.playbackSpeed;
         audioRef.current.defaultPlaybackRate = settings.playbackSpeed;
     }
  }, [settings.playbackSpeed]);

  // Gestion du MediaSession API
  useEffect(() => {
    if ('mediaSession' in navigator && playback.currentTrack) {
      const isPodcast = playback.type === 'podcast';
      const track = playback.currentTrack;
      const title = isPodcast ? (track as Episode).trackName : (track as RadioStation).name;
      const artist = isPodcast ? ((track as Episode).artistName || (track as Episode).collectionName) : (track as RadioStation).country;
      const artwork = isPodcast ? ((track as Episode).artworkUrl600 || (track as Episode).artworkUrl60) : (track as RadioStation).favicon;

      navigator.mediaSession.metadata = new MediaMetadata({
        title: title,
        artist: artist,
        artwork: artwork ? [{ src: artwork, sizes: '512x512', type: 'image/jpeg' }] : []
      });

      navigator.mediaSession.setActionHandler('play', () => {
        if (audioRef.current) { audioRef.current.play(); setPlayback(p => ({...p, isPlaying: true})); }
      });
      navigator.mediaSession.setActionHandler('pause', () => {
        if (audioRef.current) { audioRef.current.pause(); setPlayback(p => ({...p, isPlaying: false})); }
      });
      navigator.mediaSession.setActionHandler('previoustrack', () => {
         if (audioRef.current) audioRef.current.currentTime -= 15;
      });
      navigator.mediaSession.setActionHandler('nexttrack', () => {
         handleTrackEnd();
      });
    }
  }, [playback.currentTrack, playback.type]);

  // Search Logic with debounce
  useEffect(() => {
    const timeoutId = setTimeout(() => {
       if (searchTerm.trim().length > 0) {
           navigate(`/search?q=${encodeURIComponent(searchTerm)}`);
       }
    }, 500); 
    return () => clearTimeout(timeoutId);
  }, [searchTerm, navigate]);

  // Clear search term
  useEffect(() => {
      if (!location.pathname.startsWith('/search') && searchTerm) {
          setSearchTerm('');
      }
  }, [location.pathname]);

  const followedPodcasts = favorites;

  useEffect(() => {
    const load = (key: string, setter: any) => {
      const saved = localStorage.getItem(key);
      if (saved) setter(JSON.parse(saved));
    };
    load('voxstream_user', setUser);
    
    const savedSettings = localStorage.getItem('voxstream_settings');
    if (savedSettings) {
      try {
        const parsed = JSON.parse(savedSettings);
        setSettings(prev => ({ ...prev, ...parsed }));
      } catch (e) {}
    }
    
    load('voxstream_favs_v2', setFavorites);
    load('voxstream_fav_radios', setFavoriteRadios);
    load('voxstream_lang', (val: any) => {
      const code = typeof val === 'string' ? val : val?.code;
      const found = LANGUAGES.find(l => l.code === code);
      if (found) setLanguage(found);
    });
    load('voxstream_played_ids', setPlayedEpisodeIds);
    load('voxstream_saved_positions', setSavedPositions);
    load('voxstream_history', setHistory);
  }, []);

  // Spotify Callback Handler
  useEffect(() => {
    const hash = window.location.hash;
    if (hash && hash.includes('access_token=') && hash.includes('state=spotify_import')) {
      const cleanHash = hash.replace(/^#[/]?/, '');
      const params = new URLSearchParams(cleanHash);
      const accessToken = params.get('access_token');
      const pending = localStorage.getItem('podcast_ultra_spotify_import_pending');
      
      if (accessToken && pending === 'true') {
        localStorage.removeItem('podcast_ultra_spotify_import_pending');
        window.location.hash = '/settings';
        
        const doSpotifyImport = async () => {
          try {
            let shows: any[] = [];
            let nextUrl: string | null = 'https://api.spotify.com/v1/me/shows?limit=50';
            
            while (nextUrl) {
              const response = await fetch(nextUrl, {
                headers: { 'Authorization': `Bearer ${accessToken}` }
              });
              
              if (!response.ok) {
                throw new Error("Failed to fetch Spotify subscriptions");
              }
              
              const data = await response.json();
              shows = [...shows, ...(data.items || [])];
              nextUrl = data.next;
            }
            
            if (shows.length === 0) {
              alert("Aucun podcast d'abonné trouvé sur votre compte Spotify.");
              return;
            }
            
            alert(`Connexion réussie ! Recherche de ${shows.length} podcasts sur l'iTunes Store...`);
            
            const { matchPodcastOnItunes } = await import('./services/api');
            const importedPods: Podcast[] = [];
            
            for (const item of shows) {
              const show = item.show;
              try {
                const matched = await matchPodcastOnItunes(show.name, show.publisher, language.itunes);
                if (matched) {
                  importedPods.push(matched);
                }
              } catch (e) {
                console.warn(`Could not match podcast: ${show.name}`, e);
              }
            }
            
            if (importedPods.length > 0) {
              setFavorites(prev => {
                const unique = [...prev];
                importedPods.forEach(p => {
                  if (!unique.some(x => x.collectionId === p.collectionId)) {
                    unique.push(p);
                  }
                });
                return unique;
              });
              alert(`Importation réussie : ${importedPods.length} podcasts ont été importés et ajoutés à vos favoris !`);
            } else {
              alert("Aucun de vos podcasts Spotify n'a pu être trouvé sur l'iTunes Store (différence de catalogues).");
            }
          } catch (e) {
            console.error(e);
            alert("Erreur lors de la synchronisation Spotify. Vérifiez votre connexion et réessayez.");
          }
        };
        
        doSpotifyImport();
      }
    }
  }, [language]);

  useEffect(() => localStorage.setItem('voxstream_settings', JSON.stringify(settings)), [settings]);
  useEffect(() => localStorage.setItem('voxstream_lang', JSON.stringify(language)), [language]);
  useEffect(() => localStorage.setItem('voxstream_favs_v2', JSON.stringify(favorites)), [favorites]);
  useEffect(() => localStorage.setItem('voxstream_fav_radios', JSON.stringify(favoriteRadios)), [favoriteRadios]);
  useEffect(() => localStorage.setItem('voxstream_played_ids', JSON.stringify(playedEpisodeIds)), [playedEpisodeIds]);
  useEffect(() => localStorage.setItem('voxstream_saved_positions', JSON.stringify(savedPositions)), [savedPositions]);
  useEffect(() => localStorage.setItem('voxstream_history', JSON.stringify(history)), [history]);
  
  useEffect(() => {
    document.body.classList.remove('theme-light', 'theme-dark', 'theme-black');
    document.body.classList.add(`theme-${settings.theme}`);
  }, [settings.theme]);

  const togglePlayed = (id: number) => {
    setPlayedEpisodeIds(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);
  };

  const handlePlay = async (track: Episode | RadioStation, type: 'podcast' | 'radio') => {
    setPlayback(prev => ({ ...prev, currentTrack: track, isPlaying: true, type }));
    
    // Add to history if it's a podcast/episode
    if (type === 'podcast') {
        const episode = track as Episode;
        setHistory(prev => {
            const filtered = prev.filter(e => e.trackId !== episode.trackId);
            return [episode, ...filtered].slice(0, 50); // Keep last 50 episodes
        });
    }

    if (audioRef.current) {
      if (objectUrlRef.current) { URL.revokeObjectURL(objectUrlRef.current); objectUrlRef.current = null; }
      let url = type === 'podcast' ? (track as Episode).previewUrl : (track as RadioStation).url;
      if (type === 'podcast') {
        try {
          const offlineBlob = await getOfflineEpisode((track as Episode).trackId);
          if (offlineBlob) { objectUrlRef.current = URL.createObjectURL(offlineBlob); url = objectUrlRef.current; }
        } catch (e) {}
      }
      audioRef.current.src = url; 
      audioRef.current.playbackRate = settings.playbackSpeed; // Apply speed immediately
      
      let startTime = (type === 'podcast' && settings.skipIntro) ? 30 : 0;
      if (type === 'podcast' && savedPositions[(track as Episode).trackId] > 0) {
          startTime = savedPositions[(track as Episode).trackId];
      }
      audioRef.current.currentTime = startTime;

      audioRef.current.play().catch(e => console.error("Playback failed", e));
    }
  };

  const handleTrackEnd = async () => {
    if (playback.type === 'podcast' && playback.currentTrack && settings.deleteAfterListening) {
      deleteOfflineEpisode((playback.currentTrack as Episode).trackId).catch(console.error);
    }

    if (playback.queue.length > 0) { 
      const next = playback.queue[0]; 
      setPlayback(p => ({...p, queue: p.queue.slice(1)})); 
      handlePlay(next, 'podcast'); 
      return;
    }

    if (playback.type === 'podcast' && playback.currentTrack && (playback.currentTrack as Episode).collectionId) {
      const currentEp = playback.currentTrack as Episode;
      const podcastDetails = followedPodcasts.find(p => p.collectionId === currentEp.collectionId);
      
      try {
        const episodes = await getPodcastEpisodes(currentEp.collectionId!, language.itunes);
        if (episodes && episodes.length > 0) {
          const genres = podcastDetails?.genres?.map(g => g.toLowerCase()) || [];
          const isSerial = genres.some(g => ['audiobook', 'fiction', 'book', 'livre', 'roman', 'serial'].some(kw => g.includes(kw)));
          
          if (isSerial) {
            episodes.sort((a, b) => new Date(a.releaseDate).getTime() - new Date(b.releaseDate).getTime());
            if (episodes.length > 1 && episodes[0].releaseDate === episodes[1].releaseDate) {
              episodes.sort((a, b) => a.trackName.localeCompare(b.trackName, undefined, { numeric: true, sensitivity: 'base' }));
            }
          } else {
            episodes.sort((a, b) => new Date(b.releaseDate).getTime() - new Date(a.releaseDate).getTime());
          }

          const currentIndex = episodes.findIndex(e => e.trackId === currentEp.trackId);
          if (currentIndex !== -1 && currentIndex < episodes.length - 1) {
            handlePlay(episodes[currentIndex + 1], 'podcast');
            return;
          }
        }
      } catch(e) {}
    }
    
    // Play next unplayed logic
    const promises = followedPodcasts.slice(0, 10).map(p => getPodcastEpisodes(p.collectionId, p.country));
    const results = await Promise.all(promises);
    const all = results.flatMap(r => r ? r : []).sort((a, b) => new Date(b.releaseDate).getTime() - new Date(a.releaseDate).getTime());
    const nextUp = all.find(ep => !playedEpisodeIds.includes(ep.trackId) && (playback.currentTrack ? (playback.currentTrack as Episode).trackId !== ep.trackId : true));
    if (nextUp) handlePlay(nextUp, 'podcast');
    else setPlayback(p => ({...p, isPlaying: false}));
  };

  const getThemeBackgroundClass = () => {
    switch (settings.theme) {
      case 'black': return 'bg-black text-white';
      case 'light': return 'bg-slate-50 text-slate-900';
      default: return 'bg-slate-950 text-white';
    }
  };

  const marqueeStyle = `
    @keyframes marquee {
      0% { transform: translateX(0); }
      100% { transform: translateX(calc(-100% + 200px)); }
    }
    .animate-marquee {
      display: inline-block;
      white-space: nowrap;
      animation: marquee 12s linear infinite;
    }
  `;

  return (
    <div className={`flex h-screen w-full overflow-hidden relative ${getThemeBackgroundClass()}`}>
      <style>{marqueeStyle}</style>
      
      {/* Sidebar controls the Desktop Player */}
      <Sidebar 
        currentPath={location.pathname} 
        lang={language.code as LangCode} 
        accentColor={settings.accentColor}
        playback={playback}
        onToggle={() => { if(audioRef.current) { if(playback.isPlaying) audioRef.current.pause(); else audioRef.current.play(); setPlayback(p => ({...p, isPlaying: !p.isPlaying})); } }} 
        audioRef={audioRef}
        onTrackEnd={handleTrackEnd}
      />

      <main className={`flex-1 flex flex-col min-w-0 overflow-y-auto pb-24 lg:pb-32`}>
        {/* Liquid Glass Header */}
        <header className="p-4 flex items-center justify-between sticky top-0 z-30 bg-slate-900/20 backdrop-blur-3xl border-b border-white/5 transition-all">
          <div className="flex items-center gap-3 md:gap-4 flex-1">
            <Link to="/" className="lg:hidden flex items-center gap-2">
              <div className={`w-8 h-8 bg-gradient-to-br from-${settings.accentColor}-500 to-${settings.accentColor}-700 rounded-lg flex items-center justify-center shadow-lg shadow-${settings.accentColor}-500/20`}>
                <i className="fa-solid fa-microphone-lines text-white text-sm"></i>
              </div>
            </Link>
            <div className="relative flex-1 max-w-md">
              <i className="fa-solid fa-magnifying-glass absolute left-3 top-1/2 -translate-y-1/2 dark:text-slate-400 text-slate-500 text-xs"></i>
              <input 
                type="text" 
                value={searchTerm} 
                onChange={(e) => setSearchTerm(e.target.value)} 
                placeholder={t.search_placeholder} 
                className={`w-full bg-slate-800/30 backdrop-blur-md border border-white/5 rounded-full pl-9 pr-4 py-2 text-sm outline-none focus:ring-2 focus:ring-${settings.accentColor}-500/30 transition-all placeholder:text-slate-500 text-white`} 
              />
            </div>
          </div>
          
          <div className="relative flex items-center gap-2">
            <button 
              onClick={(e) => { e.stopPropagation(); navigate('/settings'); }} 
              className={`w-10 h-10 bg-white/5 backdrop-blur-md border border-white/10 rounded-full flex items-center justify-center dark:text-slate-400 text-slate-500 font-bold shadow-lg hover:bg-white/10 hover:text-white transition-all hover:scale-105`}
              title={t.settings}
            >
              <i className="fa-solid fa-gear text-sm"></i>
            </button>
          </div>

        </header>
        <Routes>
          <Route path="/" element={<DiscoverView language={language} langCode={language.code as LangCode} onSelectPodcast={(p) => navigate(`/podcast/${p.collectionId}`, { state: p })} favoritePodcasts={favorites} onToggleFavorite={(p) => setFavorites(prev => prev.some(f => f.collectionId === p.collectionId) ? prev.filter(f => f.collectionId !== p.collectionId) : [...prev, p])} accentColor={settings.accentColor} />} />
          <Route path="/episodes" element={<EpisodesView followedPodcasts={followedPodcasts} langCode={language.code as LangCode} onPlayEpisode={(e) => handlePlay(e, 'podcast')} onAddToQueue={(ep, next) => setPlayback(p => ({...p, queue: next ? [ep, ...p.queue] : [...p.queue, ep]}))} accentColor={settings.accentColor} playedEpisodeIds={playedEpisodeIds} longestPerDayOnly={settings.longestPerDayOnly} settings={settings} />} />
          
          {/* Dedicated Mobile Player Route */}
          <Route path="/player" element={
             <Player 
                playback={playback} 
                onClose={() => {}} 
                onToggle={() => { if(audioRef.current) { if(playback.isPlaying) audioRef.current.pause(); else audioRef.current.play(); setPlayback(p => ({...p, isPlaying: !p.isPlaying})); } }} 
                audioRef={audioRef} 
                onTrackEnd={handleTrackEnd} 
                langCode={language.code as LangCode} 
                accentColor={settings.accentColor} 
                onMarkPlayed={(id) => setPlayedEpisodeIds(prev => prev.includes(id) ? prev : [...prev, id])}
                onNext={handleTrackEnd}
                onPrev={() => { if(audioRef.current) audioRef.current.currentTime = 0; }}
                currentSpeed={settings.playbackSpeed}
                onSpeedChange={(speed) => setSettings(p => ({ ...p, playbackSpeed: speed }))}
                onQueueUpdate={(newQueue) => setPlayback(p => ({ ...p, queue: newQueue }))}
            />
          } />

          <Route path="/audiobooks" element={<AudiobooksView language={language} langCode={language.code as LangCode} onSelectPodcast={(p) => navigate(`/podcast/${p.collectionId}`, { state: p })} favoritePodcasts={favorites} onToggleFavorite={(p) => setFavorites(prev => prev.some(f => f.collectionId === p.collectionId) ? prev.filter(f => f.collectionId !== p.collectionId) : [...prev, p])} accentColor={settings.accentColor} />} />
          <Route path="/radio" element={<RadioView language={language} langCode={language.code as LangCode} onPlayStation={(s) => handlePlay(s, 'radio')} currentStationId={(playback.currentTrack as RadioStation)?.id} favoriteRadios={favoriteRadios} onToggleRadioFavorite={(id) => setFavoriteRadios(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id])} accentColor={settings.accentColor} />} />
          <Route path="/podcast/:id" element={<PodcastDetailView langCode={language.code as LangCode} onPlayEpisode={(e) => handlePlay(e, 'podcast')} isFavorited={(id) => favorites.some(f => f.collectionId === id)} onToggleFavorite={(p) => setFavorites(prev => prev.some(f => f.collectionId === p.collectionId) ? prev.filter(f => f.collectionId !== p.collectionId) : [...prev, p])} onAddToQueue={(ep, next) => setPlayback(p => ({...p, queue: next ? [ep, ...p.queue] : [...p.queue, ep]}))} playedEpisodeIds={playedEpisodeIds} onTogglePlayed={togglePlayed} />} />
          <Route path="/settings" element={<SettingsView langCode={language.code as LangCode} settings={settings} onUpdateSettings={(s) => setSettings(p => ({ ...p, ...s }))} currentLangCode={language.code} onUpdateLanguage={(code) => setLanguage(LANGUAGES.find(l => l.code === code)!)} onImportPodcasts={(pods) => setFavorites(prev => [...prev, ...pods])} />} />
          <Route path="/library" element={<LibraryView langCode={language.code as LangCode} accentColor={settings.accentColor} history={history} onPlayEpisode={(e) => handlePlay(e, 'podcast')} savedPositions={savedPositions} />} />
          <Route path="/recent" element={<LibraryView langCode={language.code as LangCode} accentColor={settings.accentColor} history={history} onPlayEpisode={(e) => handlePlay(e, 'podcast')} savedPositions={savedPositions} />} />
          <Route path="/playlists" element={<LibraryView langCode={language.code as LangCode} accentColor={settings.accentColor} history={history} onPlayEpisode={(e) => handlePlay(e, 'podcast')} savedPositions={savedPositions} />} />

          <Route path="/search" element={
            <SearchView 
                langCode={language.code as LangCode}
                country={language.itunes}
                favoriteIds={favorites.map(f => f.collectionId)}
                favoriteRadios={favoriteRadios}
                onToggleFavorite={(p) => setFavorites(prev => prev.some(f => f.collectionId === p.collectionId) ? prev.filter(f => f.collectionId !== p.collectionId) : [...prev, p])}
                onToggleRadioFavorite={(id) => setFavoriteRadios(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id])}
                onPlayEpisode={(e) => handlePlay(e, 'podcast')}
                onPlayStation={(s) => handlePlay(s, 'radio')}
                onSelectPodcast={(p) => navigate(`/podcast/${p.collectionId}`, { state: p })}
            />
          } />
        </Routes>
      </main>
      
      <BottomNav currentPath={location.pathname} lang={language.code as LangCode} accentColor={settings.accentColor} playback={playback} />
      <audio 
          ref={audioRef} 
          className="hidden" 
          onEnded={handleTrackEnd} 
          onTimeUpdate={() => {
              if (audioRef.current && playback.currentTrack && playback.type === 'podcast') {
                  const cur = audioRef.current.currentTime;
                  // Throttle state update roughly every 5 seconds
                  if (cur % 5 < 0.5) {
                     setSavedPositions(prev => ({...prev, [(playback.currentTrack as Episode).trackId]: cur}));
                  }
              }
          }} 
      />
    </div>
  );
}

export default function App() { return <Router><AppContent /></Router>; }
