
import React from 'react';
import { Podcast, LangCode } from '../types';
import { translations } from '../translations';

interface SubscriptionsViewProps {
  subscriptions: Podcast[];
  langCode: LangCode;
  onSelectPodcast: (podcast: Podcast) => void;
}

// SubscriptionsView displays the user's subscribed podcasts and uses translations for localization
const SubscriptionsView: React.FC<SubscriptionsViewProps> = ({ subscriptions, langCode, onSelectPodcast }) => {
  const t = translations[langCode];

  if (subscriptions.length === 0) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center p-8 text-center">
        <div className="w-24 h-24 bg-slate-900 rounded-full flex items-center justify-center mb-6 text-slate-700 text-4xl">
          <i className="fa-solid fa-rss"></i>
        </div>
        <h2 className="text-2xl font-bold mb-2">No subscriptions yet</h2>
        <p className="dark:text-slate-400 text-slate-500 max-w-md mb-8">Start following your favorite podcasts to see them here and get notified of new episodes.</p>
        <button onClick={() => window.location.hash = '/'} className="px-8 py-3 bg-indigo-600 rounded-full font-bold">{t.discover}</button>
      </div>
    );
  }

  return (
    <div className="p-8">
      <h1 className="text-3xl font-bold mb-8">{t.library}</h1>
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-6">
        {subscriptions.map((podcast) => (
          <div 
            key={podcast.collectionId}
            onClick={() => onSelectPodcast(podcast)}
            className="bg-slate-900/40 p-4 rounded-2xl border border-white/5 hover:bg-slate-800/60 transition-all cursor-pointer group"
          >
            <div className="relative mb-4 aspect-square overflow-hidden rounded-xl shadow-xl">
              <img 
                src={podcast.artworkUrl600} 
                alt={podcast.collectionName} 
                className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500"
              />
              <div className="absolute top-2 right-2 px-2 py-1 bg-indigo-500 text-[10px] font-bold rounded-lg shadow-lg">NEW</div>
            </div>
            <h3 className="font-bold text-white mb-1 truncate">{podcast.collectionName}</h3>
            <p className="text-xs dark:text-slate-400 text-slate-500 truncate">{podcast.artistName}</p>
          </div>
        ))}
      </div>
    </div>
  );
};

export default SubscriptionsView;
