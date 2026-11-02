import React, { useEffect, useState, useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';
import { searchAll, UnifiedSearchResults } from '../services/api';
import { Podcast, Episode, RadioStation, LangCode } from '../types';
import { translations } from '../translations';

interface SearchViewProps {
  langCode: LangCode;
  country: string;
  favoriteIds: number[];
  favoriteRadios: string[];
  onToggleFavorite: (podcast: Podcast) => void;
  onToggleRadioFavorite: (id: string) => void;
  onPlayEpisode: (e: Episode) => void;
  onPlayStation: (s: RadioStation) => void;
  onSelectPodcast: (p: Podcast) => void;
}

interface PodcastCardProps {
  p: Podcast; 
  isFav: boolean; 
  onSelect: (p: Podcast) => void; 
  onToggleFav: (p: Podcast) => void; 
}

const PodcastCard: React.FC<PodcastCardProps> = ({ 
  p, 
  isFav, 
  onSelect, 
  onToggleFav 
}) => (
  <div className="bg-slate-900/40 p-3 rounded-2xl border border-white/5 hover:bg-slate-800 transition-all group relative">
    <div onClick={() => onSelect(p)} className="cursor-pointer">
      <img src={p.artworkUrl600} className="w-full aspect-square rounded-xl object-cover mb-3 shadow-lg transition-transform group-hover:scale-[1.02]" />
      <h3 className="text-sm font-bold truncate text-white">{p.collectionName}</h3>
      <p className="text-[10px] text-slate-500 truncate">{p.artistName}</p>
    </div>
    <button 
      onClick={() => onToggleFav(p)}
      className={`absolute top-5 right-5 w-8 h-8 rounded-full border border-white/10 flex items-center justify-center shadow-xl transition-opacity ${isFav ? 'bg-red-500 text-white' : 'bg-slate-900/80 dark:text-slate-400 text-slate-500 hover:text-white backdrop-blur md:opacity-0 group-hover:opacity-100'}`}
    >
      <i className={`${isFav ? 'fa-solid' : 'fa-regular'} fa-heart text-xs`}></i>
    </button>
  </div>
);

const SearchView: React.FC<SearchViewProps> = ({ 
  langCode, country, favoriteIds, favoriteRadios, onToggleFavorite, onToggleRadioFavorite, 
  onPlayEpisode, onPlayStation, onSelectPodcast 
}) => {
  const [searchParams] = useSearchParams();
  const query = searchParams.get('q') || '';
  const [results, setResults] = useState<UnifiedSearchResults | null>(null);
  const [loading, setLoading] = useState(false);
  const t = translations[langCode];

  useEffect(() => {
    if (query) {
      setLoading(true);
      searchAll(query, country, langCode).then(res => {
        setResults(res);
        setLoading(false);
      });
    }
  }, [query, country, langCode]);

  if (loading) return <div className="flex-1 flex items-center justify-center h-full"><div className="animate-spin w-10 h-10 border-4 border-indigo-500 border-t-transparent rounded-full"></div></div>;
  if (!results) return null;

  return (
    <div className="p-4 md:p-8">
      <h1 className="text-2xl font-bold mb-8">{t.results} pour "{query}"</h1>
      {results.podcasts.length > 0 && (
        <section className="mb-12">
          <h2 className="text-lg font-bold dark:text-slate-400 text-slate-500 uppercase tracking-widest mb-6 px-1 flex items-center gap-2"><i className="fa-solid fa-microphone-lines text-indigo-400"></i>Podcasts</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4 md:gap-6">
            {results.podcasts.map(p => (
              <PodcastCard 
                key={p.collectionId} 
                p={p} 
                isFav={favoriteIds.includes(p.collectionId)}
                onSelect={onSelectPodcast}
                onToggleFav={onToggleFavorite}
              />
            ))}
          </div>
        </section>
      )}
      {results.radio.length > 0 && (
        <section className="mb-12">
          <h2 className="text-lg font-bold dark:text-slate-400 text-slate-500 uppercase tracking-widest mb-6 px-1 flex items-center gap-2"><i className="fa-solid fa-radio text-indigo-400"></i>Radio</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {results.radio.map(s => (
              <div key={s.id} className="bg-slate-900/40 p-3 rounded-2xl border border-white/5 hover:bg-slate-800 transition-all group flex items-center gap-4 relative">
                <div onClick={() => onPlayStation(s)} className="flex items-center gap-4 flex-1 min-w-0 cursor-pointer">
                  <img src={s.favicon} className="w-12 h-12 rounded-lg object-cover" />
                  <div className="flex-1 min-w-0"><h3 className="text-sm font-bold truncate text-white">{s.name}</h3><p className="text-[10px] text-slate-500">{s.country}</p></div>
                </div>
                <button onClick={() => onToggleRadioFavorite(s.id)} className={`w-8 h-8 rounded-full border border-white/10 flex items-center justify-center transition-all ${favoriteRadios.includes(s.id) ? 'bg-red-500 text-white' : 'text-slate-500 hover:text-white'}`}><i className={`${favoriteRadios.includes(s.id) ? 'fa-solid' : 'fa-regular'} fa-heart text-xs`}></i></button>
              </div>
            ))}
          </div>
        </section>
      )}
      {results.podcasts.length === 0 && results.radio.length === 0 && <div className="py-20 text-center text-slate-500"><i className="fa-solid fa-magnifying-glass text-5xl mb-4 opacity-10"></i><p>Aucun résultat trouvé.</p></div>}
    </div>
  );
};

export default SearchView;