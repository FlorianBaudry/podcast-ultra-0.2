
import React, { useEffect, useState, useMemo } from 'react';
import { getTrendingPodcasts, getPodcastEpisodes } from '../services/api';
import { Podcast, LangCode, AccentColor } from '../types';
import { translations } from '../translations';

interface DiscoverViewProps {
  language: { code: string, itunes: string };
  langCode: LangCode;
  onSelectPodcast: (podcast: Podcast) => void;
  favoritePodcasts: Podcast[];
  onToggleFavorite: (podcast: Podcast) => void;
  accentColor: AccentColor;
}

interface PodcastCardProps {
  podcast: Podcast; 
  isFav: boolean; 
  lastUpdated?: Date;
  langCode: LangCode;
  onSelect: (p: Podcast) => void; 
  onToggleFav: (p: Podcast) => void; 
}

const formatLastUpdated = (date?: Date, lang: string = 'fr') => {
  if (!date) return null;
  const now = new Date();
  const cappedDate = date > now ? now : date;
  
  // Strip times to check just date matching
  const dateStr = cappedDate.toDateString();
  const todayStr = now.toDateString();
  
  const yesterday = new Date();
  yesterday.setDate(now.getDate() - 1);
  const yesterdayStr = yesterday.toDateString();
  
  const diffTime = Math.abs(now.getTime() - cappedDate.getTime());
  const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24));
  
  if (dateStr === todayStr) {
    return { text: lang === 'fr' ? "Aujourd'hui" : "Today", type: 'today' };
  } else if (dateStr === yesterdayStr) {
    return { text: lang === 'fr' ? "Hier" : "Yesterday", type: 'yesterday' };
  } else if (diffDays < 7) {
    const day = cappedDate.toLocaleDateString(lang, { weekday: 'long' });
    return { text: day.charAt(0).toUpperCase() + day.slice(1), type: 'recent' };
  } else {
    return { text: cappedDate.toLocaleDateString(lang, { day: 'numeric', month: 'short' }), type: 'older' };
  }
};

const PodcastCard: React.FC<PodcastCardProps> = ({ 
  podcast, 
  isFav, 
  lastUpdated,
  langCode,
  onSelect, 
  onToggleFav 
}) => {
  const badgeInfo = formatLastUpdated(lastUpdated, langCode);
  
  const getBadgeStyle = () => {
    if (!badgeInfo) return '';
    switch (badgeInfo.type) {
      case 'today':
        return 'bg-red-500/90 text-white border-red-400/40 shadow-[0_0_12px_rgba(239,68,68,0.4)] font-black';
      case 'yesterday':
        return 'bg-amber-500/90 text-white border-amber-400/40 shadow-[0_0_8px_rgba(245,158,11,0.3)] font-extrabold';
      case 'recent':
        return 'bg-emerald-500/95 text-white border-emerald-400/40 font-bold';
      default:
        return 'bg-slate-800/80 text-slate-300 border-white/5 font-medium';
    }
  };

  return (
    <div className="bg-slate-900/30 backdrop-blur-sm p-3 md:p-4 rounded-3xl border border-white/5 hover:bg-slate-800/50 transition-all cursor-pointer group hover:border-indigo-500/20 shadow-lg relative">
      <div onClick={() => onSelect(podcast)} className="relative mb-3 aspect-square overflow-hidden rounded-2xl shadow-xl">
        <img src={podcast.artworkUrl600} alt={podcast.collectionName} className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700" />
        <div className="absolute top-2 right-2 flex flex-col items-end gap-1">
             <div className="px-2 py-1 bg-black/60 backdrop-blur-md rounded-lg text-[10px] font-bold text-white border border-white/10 uppercase tracking-tighter">
                {podcast.primaryGenreName}
             </div>
             {badgeInfo && (
                <div className={`px-2 py-0.5 rounded-md text-[9px] border flex items-center gap-1.5 transition-all duration-300 shadow-md ${getBadgeStyle()}`}>
                    {badgeInfo.type === 'today' && (
                        <span className="w-1.5 h-1.5 rounded-full bg-white animate-ping"></span>
                    )}
                    <i className="fa-regular fa-clock text-[8px]"></i>
                    {badgeInfo.text}
                </div>
             )}
        </div>
        {/* Play overlay removed as requested */}
      </div>
      <button 
        onClick={(e) => { e.stopPropagation(); onToggleFav(podcast); }}
        className={`absolute bottom-16 right-6 w-10 h-10 rounded-full border border-white/10 flex items-center justify-center shadow-xl md:opacity-0 group-hover:opacity-100 transition-opacity z-10 ${isFav ? 'bg-red-500 text-white opacity-100' : 'bg-slate-800 dark:text-slate-400 text-slate-500'}`}
      >
        <i className={`${isFav ? 'fa-solid' : 'fa-regular'} fa-heart`}></i>
      </button>
      <div onClick={() => onSelect(podcast)} className="w-full overflow-hidden relative">
        {podcast.collectionName.length > 22 ? (
          <div className="marquee-container">
            <div className="animate-marquee">
              <h3 className="font-bold text-white text-sm md:text-base mb-1 leading-tight inline-block hover:text-indigo-400 transition-colors" title={podcast.collectionName}>
                {podcast.collectionName}
                <span className="px-6 opacity-0">---</span>
                {podcast.collectionName}
                <span className="px-6 opacity-0">---</span>
              </h3>
            </div>
          </div>
        ) : (
          <h3 className="font-bold text-white text-sm md:text-base mb-1 leading-tight truncate hover:text-indigo-400 transition-colors" title={podcast.collectionName}>
            {podcast.collectionName}
          </h3>
        )}
        <p className="text-[10px] md:text-xs dark:text-slate-400 text-slate-500 truncate font-medium uppercase tracking-tight mb-1" title={podcast.artistName}>{podcast.artistName}</p>
      </div>
    </div>
  );
};

const DiscoverView: React.FC<DiscoverViewProps> = ({ language, langCode, onSelectPodcast, favoritePodcasts, onToggleFavorite, accentColor }) => {
  const [trendingPodcasts, setTrendingPodcasts] = useState<Podcast[] | null>(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('podcast_ultra_cached_trending');
      return saved ? JSON.parse(saved) : null;
    }
    return null;
  });
  const [loading, setLoading] = useState(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('podcast_ultra_cached_trending');
      const parsed = saved ? JSON.parse(saved) : null;
      return parsed === null;
    }
    return true;
  });
  const [activeCategory, setActiveCategory] = useState(() => localStorage.getItem('podcast_ultra_last_category') || 'All');
  const [refreshTrigger, setRefreshTrigger] = useState(0);
  const t = translations[langCode];

  useEffect(() => {
    const lastCategory = localStorage.getItem('podcast_ultra_trending_last_category');
    const categoryChanged = lastCategory !== activeCategory;

    // Fetch only if cache is empty, category changed, or manual refresh requested
    if (refreshTrigger === 0 && !categoryChanged && trendingPodcasts !== null) {
      return;
    }

    const load = async () => {
      setLoading(true);
      const data = await getTrendingPodcasts(language.itunes, activeCategory, refreshTrigger > 0);
      setTrendingPodcasts(data);
      setLoading(false);
      if (typeof window !== 'undefined') {
        localStorage.setItem('podcast_ultra_cached_trending', JSON.stringify(data));
        localStorage.setItem('podcast_ultra_trending_last_category', activeCategory);
      }
    };
    load();
    localStorage.setItem('podcast_ultra_last_category', activeCategory);
  }, [language, activeCategory, refreshTrigger]);

  const sortedTrending = useMemo(() => {
    return [...(trendingPodcasts || [])]
      .filter(p => !favoritePodcasts.some(f => f.collectionId === p.collectionId))
      .sort((a, b) => {
        const now = Date.now();
        const dateA = a.releaseDate ? Math.min(new Date(a.releaseDate).getTime(), now) : 0;
        const dateB = b.releaseDate ? Math.min(new Date(b.releaseDate).getTime(), now) : 0;
        return dateB - dateA;
      });
  }, [trendingPodcasts, favoritePodcasts]);

  const sortedFavorites = useMemo(() => {
    return [...favoritePodcasts]
      .filter(p => {
        const g = p.genres?.map(x => x.toLowerCase()).join(' ') || '';
        const prim = p.primaryGenreName?.toLowerCase() || '';
        
        // 1. Exclude audiobooks
        const bookKeywords = ['audiobook', 'fiction', 'book', 'livre', 'roman', 'serial'];
        const isBook = bookKeywords.some(kw => g.includes(kw) || prim.includes(kw));
        if (isBook) return false;
        
        // 2. Filter true crime by category
        const trueCrimeKeywords = ['true crime', 'criminology', 'criminologie', 'faits divers'];
        const isTrueCrime = trueCrimeKeywords.some(kw => g.includes(kw) || prim.includes(kw));
        if (activeCategory === 'True Crime') {
          return isTrueCrime;
        } else {
          return !isTrueCrime;
        }
      })
      .sort((a, b) => {
        const now = Date.now();
        const dateA = a.releaseDate ? Math.min(new Date(a.releaseDate).getTime(), now) : 0;
        const dateB = b.releaseDate ? Math.min(new Date(b.releaseDate).getTime(), now) : 0;
        return dateB - dateA; 
      });
  }, [favoritePodcasts, activeCategory]);

  return (
    <div className="p-4 md:p-8">
      <section className="mb-10">
        <div className="flex flex-col md:flex-row md:items-center justify-between mb-8 gap-4">
          <button
            onClick={() => setRefreshTrigger(t => t + 1)}
            title={langCode === 'fr' ? 'Rafraîchir les podcasts' : 'Refresh podcasts'}
            className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-bold bg-slate-900 border border-white/5 text-slate-400 hover:text-white hover:border-${accentColor}-500/30 transition-all w-fit`}
          >
            <i className={`fa-solid fa-arrows-rotate ${loading ? 'animate-spin' : ''}`}></i>
            <span className="hidden sm:inline">{langCode === 'fr' ? 'Rafraîchir' : 'Refresh'}</span>
          </button>
          <select value={activeCategory} onChange={(e) => setActiveCategory(e.target.value)} className={`bg-slate-900 border border-white/10 rounded-xl px-4 py-2 text-xs font-bold text-slate-300 outline-none focus:ring-2 focus:ring-${accentColor}-500`}>
            {Object.keys(translations[langCode].categories).map(catKey => <option key={catKey} value={catKey}>{translations[langCode].categories[catKey]}</option>)}
          </select>
        </div>

        {sortedFavorites.length > 0 && (
          <div className="mb-12 animate-in fade-in slide-in-from-top-4 duration-500">
            <div className="flex items-center gap-2 mb-6"><i className="fa-solid fa-heart text-red-500"></i><h3 className="text-xl font-bold">{t.your_favorites}</h3></div>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4 md:gap-6">
              {sortedFavorites.map(p => (
                <PodcastCard 
                  key={`fav-${p.collectionId}`} 
                  podcast={p} 
                  isFav={true}
                  lastUpdated={p.releaseDate ? new Date(p.releaseDate) : undefined}
                  langCode={langCode}
                  onSelect={onSelectPodcast}
                  onToggleFav={onToggleFavorite}
                />
              ))}
            </div>
            <div className="h-px bg-white/5 my-10"></div>
          </div>
        )}
        
        
        {loading && (!trendingPodcasts || trendingPodcasts.length === 0) ? <div className="flex justify-center py-20"><div className={`animate-spin w-10 h-10 border-4 border-${accentColor}-500 border-t-transparent rounded-full`}></div></div> : (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4 md:gap-6">
            {sortedTrending.map((podcast) => (
              <PodcastCard 
                key={podcast.collectionId} 
                podcast={podcast} 
                isFav={false} 
                lastUpdated={podcast.releaseDate ? new Date(podcast.releaseDate) : undefined}
                langCode={langCode}
                onSelect={onSelectPodcast}
                onToggleFav={onToggleFavorite}
              />
            ))}
          </div>
        )}
      </section>
    </div>
  );
};

export default DiscoverView;
