import React from 'react';
import { LangCode, Episode, AccentColor } from '../types';
import { translations } from '../translations';
import RecentEpisodesView from './RecentEpisodesView';

interface LibraryViewProps {
  langCode: LangCode;
  accentColor: AccentColor;
  history: Episode[];
  onPlayEpisode: (episode: Episode) => void;
  savedPositions?: Record<string, number>;
}

const LibraryView: React.FC<LibraryViewProps> = ({ 
    langCode, history, onPlayEpisode, savedPositions = {}
}) => {
  const t = translations[langCode];

  return (
    <div className="p-4 md:p-8">
      <div className="flex items-center gap-4 mb-8">
        <div className="w-12 h-12 rounded-2xl bg-indigo-500/10 flex items-center justify-center text-indigo-500">
            <i className="fa-solid fa-clock-rotate-left text-2xl"></i>
        </div>
        <h1 className="text-2xl md:text-3xl font-extrabold tracking-tight">{t.library || 'Bibliothèque'}</h1>
      </div>
      
      {/* Embedded History */}
      <div className="animate-in fade-in slide-in-from-bottom-2 duration-300">
         <div className="-mx-4 md:-mx-8">
             <style>{`.history-title-hide h1 { display: none; }`}</style>
             <div className="history-title-hide">
             <RecentEpisodesView 
                    history={history} 
                    langCode={langCode} 
                    onPlayEpisode={onPlayEpisode}
                    savedPositions={savedPositions}
                />
             </div>
         </div>
      </div>
    </div>
  );
};

export default LibraryView;
