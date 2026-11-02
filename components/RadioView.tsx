
import React, { useEffect, useState } from 'react';
import { getRadioStations, getRadioStationsByIds } from '../services/api';
import { RadioStation, LangCode, AccentColor, LANGUAGES } from '../types';
import { translations } from '../translations';

interface RadioViewProps {
  language: { code: string, name: string, radioSearch: string };
  langCode: LangCode;
  onPlayStation: (station: RadioStation) => void;
  currentStationId?: string;
  favoriteRadios: string[];
  onToggleRadioFavorite: (id: string) => void;
  accentColor: AccentColor;
}

interface StationCardProps {
  station: RadioStation; 
  isPlaying: boolean; 
  isFavorite: boolean; 
  onPlay: (s: RadioStation) => void; 
  onToggleFav: (id: string) => void; 
}

const generateRadioIcon = (name: string) => {
  const letters = encodeURIComponent((name || 'RD').substring(0, 2).toUpperCase());
  return `data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100"><rect width="100" height="100" fill="%236366f1"/><text x="50%" y="50%" fill="white" font-size="40" font-family="sans-serif" font-weight="bold" dominant-baseline="middle" text-anchor="middle">${letters}</text></svg>`;
};

const StationCard: React.FC<StationCardProps> = ({ 
  station, 
  isPlaying, 
  isFavorite, 
  onPlay, 
  onToggleFav, 
}) => (
  <div 
    className={`flex flex-col p-3 md:p-4 rounded-3xl border transition-all group relative backdrop-blur-md ${
      isPlaying
        ? 'bg-indigo-600/20 border-indigo-500/30' 
        : 'bg-slate-900/30 border-white/5 hover:bg-slate-800/40 hover:border-white/10'
    }`}
  >
    <div className="flex items-center gap-4">
      <div 
        onClick={() => onPlay(station)}
        className="w-14 h-14 md:w-16 md:h-16 rounded-2xl overflow-hidden bg-slate-800 relative shadow-xl flex-shrink-0 cursor-pointer"
      >
        <img 
            src={station.favicon || generateRadioIcon(station.name)} 
            onError={(e) => { (e.target as HTMLImageElement).src = generateRadioIcon(station.name); }} 
            alt={station.name} 
            className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500" 
        />
        <div className="absolute inset-0 bg-black/40 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
          <i className={`fa-solid ${isPlaying ? 'fa-pause' : 'fa-play'} text-white`}></i>
        </div>
      </div>
      <div className="flex-1 min-w-0" onClick={() => onPlay(station)}>
        <h3 className="font-bold text-white truncate text-sm md:text-base cursor-pointer group-hover:text-indigo-400 transition-colors">
          {station.name}
        </h3>
        <p className="text-[10px] md:text-xs dark:text-slate-400 text-slate-500 mb-1 font-medium">{station.country}</p>
      </div>
      <div className="flex flex-col gap-2">
          <button 
            onClick={(e) => { e.stopPropagation(); onToggleFav(station.id); }}
            className={`w-8 h-8 rounded-full border border-white/10 flex items-center justify-center transition-all ${isFavorite ? 'bg-red-500 text-white border-red-500 shadow-lg shadow-red-500/20' : 'text-slate-500 hover:text-white hover:bg-white/5'}`}
          >
            <i className={`${isFavorite ? 'fa-solid' : 'fa-regular'} fa-heart text-[10px]`}></i>
          </button>
      </div>
    </div>
  </div>
);

const RadioView: React.FC<RadioViewProps> = ({ language, langCode, onPlayStation, currentStationId, favoriteRadios, onToggleRadioFavorite, accentColor }) => {
  const [stations, setStations] = useState<RadioStation[] | null>(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('podcast_ultra_cached_radio');
      return saved ? JSON.parse(saved) : null;
    }
    return null;
  });
  const [favoriteStations, setFavoriteStations] = useState<RadioStation[]>([]);
  const [loading, setLoading] = useState(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('podcast_ultra_cached_radio');
      const parsed = saved ? JSON.parse(saved) : null;
      return parsed === null;
    }
    return true;
  });
  const [refreshTrigger, setRefreshTrigger] = useState(0);
  const t = translations[langCode];

  // Charger les favoris explicitement par UUID
  useEffect(() => {
    if (favoriteRadios.length > 0) {
      getRadioStationsByIds(favoriteRadios).then(setFavoriteStations);
    } else {
      setFavoriteStations([]);
    }
  }, [favoriteRadios]);

  useEffect(() => {
    // Fetch only if cache is empty or manual refresh requested
    if (refreshTrigger === 0 && stations !== null) {
      return;
    }

    setLoading(true);
    getRadioStations(language.radioSearch, language.code, refreshTrigger > 0).then(data => {
      setStations(data);
      setLoading(false);
      if (typeof window !== 'undefined') {
        localStorage.setItem('podcast_ultra_cached_radio', JSON.stringify(data));
      }
    });
  }, [language, refreshTrigger]);

  if (loading && (!stations || stations.length === 0)) return <div className="flex-1 flex items-center justify-center h-full"><div className={`animate-spin w-10 h-10 border-4 border-${accentColor}-500 border-t-transparent rounded-full`}></div></div>;

  return (
    <div className="p-4 md:p-8 max-w-7xl mx-auto">
      <div className="flex justify-between items-center mb-8 gap-4">
        <h2 className="text-xl font-bold text-white">{t.world_radio || 'Radio Mondiale'}</h2>
        <button
          onClick={() => setRefreshTrigger(t => t + 1)}
          title={langCode === 'fr' ? 'Rafraîchir les radios' : 'Refresh radios'}
          className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-bold bg-slate-900 border border-white/5 text-slate-400 hover:text-white hover:border-${accentColor}-500/30 transition-all w-fit`}
        >
          <i className={`fa-solid fa-arrows-rotate ${loading ? 'animate-spin' : ''}`}></i>
          <span className="hidden sm:inline">{langCode === 'fr' ? 'Rafraîchir' : 'Refresh'}</span>
        </button>
      </div>
      {favoriteStations.length > 0 && (
        <div className="mb-14 animate-in fade-in slide-in-from-top-4 duration-500">
          <div className="flex items-center gap-3 mb-6">
            <h3 className="text-xl font-bold tracking-tight text-white">{t.your_favorites}</h3>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 md:gap-6">
            {favoriteStations.map(s => (
              <StationCard 
                key={`fav-rad-${s.id}`} 
                station={s}
                isPlaying={currentStationId === s.id}
                isFavorite={true}
                onPlay={onPlayStation}
                onToggleFav={onToggleRadioFavorite}
              />
            ))}
          </div>
          <div className="h-px bg-white/5 my-10"></div>
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 md:gap-6">
        {(stations || []).filter(s => !favoriteRadios.includes(s.id)).map(station => (
          <StationCard 
            key={station.id} 
            station={station}
            isPlaying={currentStationId === station.id}
            isFavorite={false}
            onPlay={onPlayStation}
            onToggleFav={onToggleRadioFavorite}
          />
        ))}
      </div>
    </div>
  );
};

export default RadioView;
