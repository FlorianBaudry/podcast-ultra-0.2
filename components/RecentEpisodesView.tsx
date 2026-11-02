
import React from 'react';
import { Episode, LangCode } from '../types';
import { translations } from '../translations';

interface RecentEpisodesViewProps {
  history: Episode[];
  langCode: LangCode;
  onPlayEpisode: (episode: Episode) => void;
  savedPositions?: Record<string, number>;
}

const RecentEpisodesView: React.FC<RecentEpisodesViewProps> = ({ history, langCode, onPlayEpisode, savedPositions = {} }) => {
  const t = translations[langCode];

  return (
    <div className="p-4 md:p-8">
      <div className="mb-10">
        <h1 className="text-2xl md:text-3xl font-bold mb-2">{t.library}</h1>
      </div>

      {(!history || history.length === 0) ? (
        <div className="flex flex-col items-center justify-center py-20 text-center text-slate-500">
          <i className="fa-solid fa-clock-rotate-left text-5xl mb-4 opacity-10"></i>
          <p>Votre historique d&apos;écoute apparaîtra ici.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {history.map((ep, idx) => {
            const pos = savedPositions[ep.trackId] || 0;
            const dur = ep.trackTimeMillis ? ep.trackTimeMillis / 1000 : 0;
            const pct = dur > 0 ? Math.min(100, (pos / dur) * 100) : 0;

            const fmt = (s: number) => {
              const h = Math.floor(s / 3600);
              const m = Math.floor((s % 3600) / 60);
              return h > 0 ? `${h}h ${m.toString().padStart(2, '0')}m` : `${m}m`;
            };
            return (
              <div 
                key={`${ep.trackId}-${idx}`} 
                onClick={() => onPlayEpisode(ep)}
                className="bg-slate-900/40 p-3 rounded-2xl border border-white/5 hover:bg-slate-800 transition-all cursor-pointer group flex gap-4 items-center"
              >
                <img src={ep.artworkUrl160 || ep.artworkUrl60} className="w-14 h-14 rounded-xl object-cover shadow-md group-hover:scale-105 transition-transform flex-shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-[10px] font-bold text-indigo-400 uppercase truncate mb-0.5">{ep.collectionName}</p>
                  <h3 className="text-sm font-bold text-white leading-tight line-clamp-1 group-hover:text-indigo-300 transition-colors">{ep.trackName}</h3>
                  <div className="flex items-center gap-2 mt-1.5">
                    <div className="flex-1 h-1 bg-slate-700 rounded-full overflow-hidden">
                      <div className="h-full bg-indigo-500 rounded-full transition-all" style={{ width: `${pct}%` }}></div>
                    </div>
                    {pct > 0 && dur > 0 && (
                      <span className="text-[9px] text-slate-500 font-medium tabular-nums flex-shrink-0">
                        {fmt(pos)} / {fmt(dur)}
                      </span>
                    )}
                  </div>
                </div>
                <div className="w-8 h-8 rounded-full bg-white/5 flex items-center justify-center dark:text-slate-400 text-slate-500 group-hover:bg-indigo-500 group-hover:text-white transition-all flex-shrink-0">
                   <i className="fa-solid fa-play text-xs"></i>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default RecentEpisodesView;
