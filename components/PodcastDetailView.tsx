
import React, { useEffect, useState } from 'react';
import { useParams, useLocation } from 'react-router-dom';
import { getPodcastEpisodes } from '../services/api';
import { getPodcastInsight } from '../services/insights';
import { saveOfflineEpisode, deleteOfflineEpisode, getAllOfflineIds } from '../services/offline';
import { Podcast, Episode, Playlist, LangCode, LANGUAGES } from '../types';
import { translations } from '../translations';

interface PodcastDetailViewProps {
  langCode: LangCode;
  onPlayEpisode: (episode: Episode) => void;
  isFavorited: (id: number) => boolean;
  onToggleFavorite: (podcast: Podcast) => void;
  onAddToQueue: (episode: Episode, next: boolean) => void;
  playedEpisodeIds: number[];
  onTogglePlayed: (id: number) => void;
}

const PodcastDetailView: React.FC<PodcastDetailViewProps> = ({ 
  langCode, onPlayEpisode, isFavorited, onToggleFavorite, 
  onAddToQueue, playedEpisodeIds, onTogglePlayed
}) => {
  const { id } = useParams();
  const location = useLocation();
  const podcast = location.state as Podcast;
  const [episodes, setEpisodes] = useState<Episode[]>([]);
  const [loading, setLoading] = useState(true);
  const [podcastInsight, setPodcastInsight] = useState<string | null>(null);
  const [downloadedIds, setDownloadedIds] = useState<number[]>([]);
  const [downloadingIds, setDownloadingIds] = useState<number[]>([]);
  const t = translations[langCode];
  
  const currentLangName = LANGUAGES.find(l => l.code === langCode)?.name || 'English';

  const isAudiobook = podcast?.genres?.some(g => {
    const genre = g.toLowerCase();
    return ['audiobook', 'fiction', 'book', 'livre', 'roman', 'serial'].some(kw => genre.includes(kw));
  });

  useEffect(() => {
    if (id && podcast) {
      getPodcastEpisodes(Number(id), undefined, podcast?.feedUrl).then(data => {
        let sortedData = [...data];
        
        if (isAudiobook) {
          sortedData.sort((a, b) => new Date(a.releaseDate).getTime() - new Date(b.releaseDate).getTime());
          if (sortedData.length > 1 && sortedData[0].releaseDate === sortedData[1].releaseDate) {
             sortedData.sort((a, b) => a.trackName.localeCompare(b.trackName, undefined, { numeric: true, sensitivity: 'base' }));
          }
        } else {
          sortedData.sort((a, b) => new Date(b.releaseDate).getTime() - new Date(a.releaseDate).getTime());
        }

        setEpisodes(sortedData);
        setLoading(false);
      });
      getAllOfflineIds().then(setDownloadedIds);
      getPodcastInsight(podcast.collectionName, podcast.artistName, podcast.genres, currentLangName).then(setPodcastInsight);
    }
  }, [id, podcast, isAudiobook, currentLangName]);

  const handleDownload = async (episode: Episode) => {
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
    } catch (e) {} finally { setDownloadingIds(prev => prev.filter(i => i !== episode.trackId)); }
  };

  if (!podcast) return <div className="p-8">Podcast non trouvé</div>;

  return (
    <div className="flex-1">
      <div className="p-6 md:p-8 bg-gradient-to-b from-indigo-900/20 to-transparent flex flex-col md:flex-row gap-6 md:gap-8 items-center md:items-end">
        <img src={podcast.artworkUrl600} className="w-40 h-40 md:w-64 md:h-64 rounded-3xl shadow-2xl object-cover" />
        <div className="flex-1 text-center md:text-left">
          <h1 className="text-3xl md:text-5xl font-extrabold mb-4 text-white">{podcast.collectionName}</h1>
          {podcastInsight ? (
            <div className="mb-6 max-w-2xl text-slate-300 font-medium italic text-sm md:text-base leading-relaxed opacity-90">
               {podcastInsight}
            </div>
          ) : podcast.description && (
            <div className="mb-6 max-w-2xl text-slate-400 text-xs md:text-sm leading-relaxed line-clamp-3">
               {podcast.description.replace(/<[^>]*>/g, '')}
            </div>
          )}
          <div className="flex flex-wrap items-center justify-center md:justify-start gap-3">
            <button onClick={() => episodes[0] && onPlayEpisode(episodes[0])} className="px-8 py-3 bg-indigo-500 hover:bg-indigo-400 text-white font-bold rounded-full transition-all flex items-center gap-2"><i className="fa-solid fa-play"></i> {isAudiobook ? "Commencer" : t.latest}</button>
            <button onClick={() => onToggleFavorite(podcast)} className={`px-6 py-3 rounded-full border border-white/20 flex items-center justify-center gap-2 transition-colors font-bold ${isFavorited(podcast.collectionId) ? 'bg-red-500 text-white border-red-500' : 'hover:bg-white/5 text-white'}`}>
                <i className={`${isFavorited(podcast.collectionId) ? 'fa-solid' : 'fa-regular'} fa-heart`}></i>
                {isFavorited(podcast.collectionId) ? "Favori" : "Suivre"}
            </button>
          </div>
        </div>
      </div>
      <div className="p-4 md:p-8">
        <h2 className="text-xl md:text-2xl font-bold mb-6 text-white">{isAudiobook ? "Chapitres" : t.episodes}</h2>
        <div className="space-y-2">
          {episodes.map((episode, index) => (
            <div key={episode.trackId} className={`group p-3 md:p-4 rounded-3xl hover:bg-white/5 border-b border-white/5 flex items-center gap-4 md:gap-6 ${playedEpisodeIds.includes(episode.trackId) ? 'opacity-50' : ''}`}>
              <div className="relative w-12 h-12 md:w-16 md:h-16 flex-shrink-0 group-hover:scale-105 transition-transform">
                <img 
                  src={episode.artworkUrl160 || episode.artworkUrl60 || podcast.artworkUrl600 || podcast.artworkUrl100} 
                  className="w-full h-full object-cover rounded-xl shadow-lg border border-white/5" 
                  alt={episode.trackName} 
                />
                <button 
                  onClick={() => onPlayEpisode(episode)} 
                  className="absolute inset-0 flex items-center justify-center bg-black/40 bg-opacity-0 group-hover:bg-opacity-100 transition-all rounded-xl"
                >
                  <div className="w-8 h-8 rounded-full bg-indigo-500 flex items-center justify-center text-white scale-75 md:scale-90 group-hover:scale-100 transition-transform shadow-xl">
                    <i className="fa-solid fa-play text-[10px]"></i>
                  </div>
                </button>
              </div>
              
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <span className="text-[10px] font-bold text-slate-500 w-5">{episodes.length - index}</span>
                  <h4 className="font-bold text-white truncate text-sm md:text-base">{episode.trackName}</h4>
                  {downloadedIds.includes(episode.trackId) && <span className="bg-emerald-500/10 text-emerald-500 text-[8px] font-bold px-1.5 py-0.5 rounded border border-emerald-500/20 uppercase tracking-widest">{t.offline}</span>}
                  {playedEpisodeIds.includes(episode.trackId) && <span className="text-emerald-500 text-[10px] ml-1"><i className="fa-solid fa-check"></i></span>}
                </div>
                <div className="text-[10px] md:text-xs text-slate-500 flex items-center gap-3">
                  <span>{new Date(episode.releaseDate).toLocaleDateString()}</span>
                  <span>•</span>
                  <span>{Math.floor(episode.trackTimeMillis / 60000)} mins</span>
                  <button onClick={() => onTogglePlayed(episode.trackId)} className="ml-auto text-slate-500 hover:text-indigo-400 font-medium transition-colors" title={playedEpisodeIds.includes(episode.trackId) ? t.mark_unplayed : t.mark_played}>
                    <i className={`fa-solid ${playedEpisodeIds.includes(episode.trackId) ? 'fa-circle-check text-emerald-500' : 'fa-circle-check opacity-20'}`}></i>
                  </button>
                </div>
              </div>
              <div className="flex flex-col sm:flex-row items-center gap-2">
                <button 
                  onClick={() => onAddToQueue(episode, false)}
                  className="w-8 h-8 rounded-full border border-white/10 flex items-center justify-center dark:text-slate-400 text-slate-500 hover:text-white hover:bg-white/10 transition-colors relative z-20"
                  title={t.add_to_queue}
                >
                  <i className="fa-solid fa-list-ul text-xs"></i>
                </button>
                <button onClick={() => handleDownload(episode)} className={`w-8 h-8 rounded-full border border-white/10 flex items-center justify-center transition-colors relative z-20 ${downloadedIds.includes(episode.trackId) ? 'text-emerald-400 border-emerald-500/20' : 'dark:text-slate-400 text-slate-500 hover:text-white hover:bg-white/10'}`}>
                    <i className={`fa-solid ${downloadingIds.includes(episode.trackId) ? 'fa-circle-notch animate-spin' : downloadedIds.includes(episode.trackId) ? 'fa-trash' : 'fa-download'} text-xs`}></i>
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default PodcastDetailView;
