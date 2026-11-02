
import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { PlaybackState, Episode, RadioStation, LangCode, AccentColor, LANGUAGES } from '../types';
import { translations } from '../translations';

interface PlayerProps {
  playback: PlaybackState;
  onToggle: () => void;
  audioRef: React.RefObject<HTMLAudioElement>;
  onTrackEnd: () => void;
  langCode: LangCode;
  onClose: () => void;
  accentColor: AccentColor;
  onMarkPlayed: (id: number) => void;
  onNext?: () => void;
  onPrev?: () => void;
  currentSpeed?: number;
  onSpeedChange?: (speed: number) => void;
  onQueueUpdate?: (queue: Episode[]) => void;
}

const Player: React.FC<PlayerProps> = ({ playback, onToggle, audioRef, onTrackEnd, langCode, onClose, accentColor, onMarkPlayed, onNext, onPrev, currentSpeed = 1, onSpeedChange, onQueueUpdate }) => {
  const [progress, setProgress] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [hasMarkedPlayed, setHasMarkedPlayed] = useState(false);
  const [viewMode, setViewMode] = useState<'player' | 'queue'>('player');
  const t = translations[langCode];

  // Reset marked state on track change
  useEffect(() => {
    setHasMarkedPlayed(false);
  }, [(playback.currentTrack as Episode)?.trackId]);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const updateProgress = () => {
      const cur = audio.currentTime;
      setCurrentTime(cur);
      setProgress((cur / audio.duration) * 100 || 0);
      setDuration(audio.duration || 0);

      // Mark as played if listened for more than 60 seconds and it's a podcast
      if (playback.type === 'podcast' && !hasMarkedPlayed && cur > 60 && playback.currentTrack) {
        onMarkPlayed((playback.currentTrack as Episode).trackId);
        setHasMarkedPlayed(true);
      }
    };

    audio.addEventListener('timeupdate', updateProgress);
    return () => audio.removeEventListener('timeupdate', updateProgress);
  }, [audioRef, hasMarkedPlayed, playback.type, playback.currentTrack, onMarkPlayed]);

  const skipTime = (seconds: number) => {
    if (audioRef.current) {
      let newTime = audioRef.current.currentTime + seconds;
      if (newTime < 0) newTime = 0;
      if (newTime > audioRef.current.duration) newTime = audioRef.current.duration;
      audioRef.current.currentTime = newTime;
    }
  };

  const formatTime = (time: number) => {
    if (isNaN(time)) return "0:00";
    const minutes = Math.floor(time / 60);
    const seconds = Math.floor(time % 60);
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  const moveItem = (index: number, direction: -1 | 1) => {
    if (!onQueueUpdate) return;
    const newQueue = [...playback.queue];
    if (direction === -1 && index > 0) {
      [newQueue[index], newQueue[index - 1]] = [newQueue[index - 1], newQueue[index]];
    } else if (direction === 1 && index < newQueue.length - 1) {
      [newQueue[index], newQueue[index + 1]] = [newQueue[index + 1], newQueue[index]];
    }
    onQueueUpdate(newQueue);
  };

  const removeItem = (index: number) => {
    if (!onQueueUpdate) return;
    const newQueue = playback.queue.filter((_, i) => i !== index);
    onQueueUpdate(newQueue);
  };

  if (!playback.currentTrack) {
    return (
        <div className="flex flex-col items-center justify-center h-full p-8 text-center bg-gradient-to-b from-slate-900 to-slate-950">
            <div className="w-48 h-48 bg-slate-800/50 rounded-[2.5rem] flex items-center justify-center mb-8 shadow-inner border border-white/5">
                <i className="fa-solid fa-music text-6xl text-slate-700"></i>
            </div>
            <h2 className="text-2xl font-bold text-white mb-2">Aucune lecture</h2>
            <p className="text-slate-500">Sélectionnez un podcast ou une radio pour commencer l'écoute.</p>
        </div>
    );
  }

  const track = playback.currentTrack;
  const isPodcast = playback.type === 'podcast';
  const artwork = isPodcast ? (track as Episode).artworkUrl600 : (track as RadioStation).favicon;
  const title = isPodcast ? (track as Episode).trackName : (track as RadioStation).name;
  const subtitle = isPodcast ? (track as Episode).collectionName : (track as RadioStation).country;

  return (
    <div className="flex flex-col h-full bg-slate-950 overflow-hidden relative">
       
       {/* Header - Z-Index augmenté à 60 pour être au-dessus de la file d'attente (z-50) */}
       <div className="absolute top-0 left-0 right-0 flex items-center justify-between p-4 pt-6 z-[60] h-16 bg-transparent pointer-events-none">
          <button onClick={() => setViewMode(viewMode === 'player' ? 'queue' : 'player')} className={`w-10 h-10 rounded-full flex items-center justify-center transition-colors backdrop-blur-md pointer-events-auto ${viewMode === 'queue' ? `bg-${accentColor}-500/20 text-${accentColor}-400 border border-${accentColor}-500/50` : 'dark:text-slate-400 text-slate-500 hover:text-white bg-slate-900/50'}`}>
              <i className={`fa-solid ${viewMode === 'queue' ? 'fa-xmark' : 'fa-list'}`}></i>
          </button>
          
          <div className="flex flex-col items-center pointer-events-none">
             <span className="text-[10px] font-bold dark:text-slate-400 text-slate-500/80 uppercase tracking-widest shadow-black drop-shadow-md">{viewMode === 'queue' ? t.up_next : isPodcast ? 'PODCAST' : 'RADIO'}</span>
          </div>

          <div className="flex items-center gap-3 pointer-events-auto">
              <Link to="/recent" className="w-10 h-10 rounded-full bg-slate-900/50 backdrop-blur-md flex items-center justify-center dark:text-slate-400 text-slate-500 hover:text-white transition-colors">
                  <i className="fa-solid fa-clock-rotate-left"></i>
              </Link>
          </div>
       </div>

       {/* Main Player Content */}
       <div className={`flex-1 flex flex-col items-center justify-end px-6 pb-6 pt-24 transition-opacity duration-300 overflow-hidden ${viewMode === 'player' ? 'opacity-100' : 'opacity-0 pointer-events-none absolute inset-0 pt-20'}`}>
            
            {/* Artwork - Maximized Space */}
            <div className="flex-1 w-full min-h-0 flex items-center justify-center py-4 relative z-0">
                <div className="relative w-full h-full flex items-center justify-center">
                    <img src={artwork} alt={title} className="w-full h-full object-contain rounded-3xl drop-shadow-2xl max-h-[70vh]" />
                </div>
            </div>

            {/* Controls Section - Pushed to bottom */}
            <div className="w-full max-w-md flex-shrink-0 relative z-20 pb-2">
                
                {/* Info & Title */}
                <div className="text-center w-full mb-6">
                    <div className="w-full overflow-hidden relative h-7 mb-1">
                        {title.length > 30 ? (
                            <div className="marquee-container">
                                <div className="animate-marquee">
                                    <Link to={`/search?q=${encodeURIComponent(subtitle)}`} onClick={onClose} className="text-xl font-black text-white leading-tight px-4 inline-block hover:text-indigo-400 transition-colors cursor-pointer">
                                        {title}
                                        <span className="px-6 opacity-0">---</span>
                                        {title}
                                        <span className="px-6 opacity-0">---</span>
                                    </Link>
                                </div>
                            </div>
                        ) : (
                            <Link to={`/search?q=${encodeURIComponent(subtitle)}`} onClick={onClose} className="text-xl font-black text-white leading-tight px-4 hover:text-indigo-400 transition-colors cursor-pointer truncate block">
                                {title}
                            </Link>
                        )}
                    </div>
                    <Link to={`/search?q=${encodeURIComponent(subtitle)}`} onClick={onClose} className={`text-xs font-bold text-${accentColor}-400 uppercase tracking-widest line-clamp-1 hover:underline cursor-pointer block`}>{subtitle}</Link>
                </div>

                {/* Progress Bar (Only for Podcasts) */}
                <div className="mb-6 px-1">
                    {isPodcast ? (
                        <>
                            <div 
                                className="h-1.5 bg-slate-800 rounded-full mb-2 cursor-pointer relative overflow-hidden group touch-none"
                                onClick={(e) => {
                                    if (audioRef.current) {
                                        const rect = e.currentTarget.getBoundingClientRect();
                                        const x = e.clientX - rect.left;
                                        const clickedPercent = x / rect.width;
                                        audioRef.current.currentTime = clickedPercent * audioRef.current.duration;
                                    }
                                }}
                            >
                                <div className={`absolute top-0 left-0 h-full bg-${accentColor}-500 rounded-full`} style={{ width: `${progress}%` }}></div>
                            </div>
                            <div className="flex justify-between text-[10px] font-bold text-slate-500 uppercase tracking-wider">
                                <span>{formatTime(currentTime)}</span>
                                <span>{formatTime(duration)}</span>
                            </div>
                        </>
                    ) : (
                        <div className="flex items-center justify-center gap-2 py-2">
                            <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse"></span>
                            <span className="text-xs font-bold text-red-500 uppercase tracking-widest">LIVE</span>
                        </div>
                    )}
                </div>

                {/* Main Buttons */}
                <div className="flex items-center justify-between px-2">
                    <button onClick={onPrev} className="w-10 h-10 flex items-center justify-center text-slate-500 hover:text-white transition-colors active:scale-90">
                        <i className="fa-solid fa-backward-step text-xl"></i>
                    </button>

                    <button onClick={() => skipTime(-30)} className="w-12 h-12 rounded-full dark:text-slate-400 text-slate-500 hover:text-white flex items-center justify-center active:scale-90 transition-transform bg-slate-900 border border-white/5">
                        <i className="fa-solid fa-rotate-left text-sm"></i>
                    </button>

                    <button 
                        onClick={onToggle}
                        className={`w-16 h-16 rounded-[2rem] bg-${accentColor}-600 text-white flex items-center justify-center shadow-[0_10px_40px_-10px_rgba(0,0,0,0.5)] active:scale-95 transition-transform`}
                    >
                        <i className={`fa-solid ${playback.isPlaying ? 'fa-pause' : 'fa-play'} text-2xl ml-1`}></i>
                    </button>

                    <button onClick={() => skipTime(30)} className="w-12 h-12 rounded-full dark:text-slate-400 text-slate-500 hover:text-white flex items-center justify-center active:scale-90 transition-transform bg-slate-900 border border-white/5">
                        <i className="fa-solid fa-rotate-right text-sm"></i>
                    </button>

                    <button onClick={onNext} className="w-10 h-10 flex items-center justify-center text-slate-500 hover:text-white transition-colors active:scale-90">
                        <i className="fa-solid fa-forward-step text-xl"></i>
                    </button>
                </div>
            </div>
       </div>

       {/* Queue View Overlay - Z-Index 50 (below header z-60) */}
       {viewMode === 'queue' && (
           <div className="absolute inset-0 top-0 bottom-20 bg-slate-950/95 backdrop-blur-xl z-50 p-6 pt-24 overflow-y-auto animate-in fade-in zoom-in-95 duration-200">
                <div className="flex items-center gap-3 mb-6 p-4 bg-slate-900 rounded-2xl border border-white/5">
                    <img src={artwork} className="w-12 h-12 rounded-lg object-contain bg-black" />
                    <div className="flex-1 min-w-0">
                        <p className={`text-[10px] font-bold text-${accentColor}-400 uppercase tracking-wider mb-1`}>{t.now_playing}</p>
                        <Link to={`/search?q=${encodeURIComponent(subtitle)}`} onClick={onClose} className="text-sm font-bold text-white truncate hover:underline block">{title}</Link>
                    </div>
                    <div className="w-6 h-6 rounded-full bg-white/10 flex items-center justify-center">
                        <i className="fa-solid fa-volume-high text-xs text-white"></i>
                    </div>
                </div>

                <h3 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 pl-1">{t.up_next} ({playback.queue.length})</h3>
                
                {playback.queue.length === 0 ? (
                    <div className="flex flex-col items-center justify-center py-10 opacity-50">
                        <i className="fa-solid fa-list-ul text-3xl mb-2"></i>
                        <p className="text-xs">Queue is empty</p>
                    </div>
                ) : (
                    <div className="space-y-3">
                        {playback.queue.map((ep, i) => (
                            <div key={`${ep.trackId}-${i}`} className="flex items-center gap-3 group">
                                <span className="text-slate-600 font-bold text-xs w-4 text-center">{i + 1}</span>
                                
                                <div className="flex-1 min-w-0 flex items-center gap-3 p-3 rounded-xl bg-slate-900/50 border border-white/5">
                                    <img src={ep.artworkUrl60} className="w-10 h-10 rounded-lg opacity-80" />
                                    <div className="flex-1 min-w-0">
                                        <p className="text-xs font-bold text-slate-300 truncate">{ep.trackName}</p>
                                        <p className="text-[10px] text-slate-500 truncate">{ep.collectionName}</p>
                                    </div>
                                </div>

                                {/* Reorder & Delete Controls */}
                                <div className="flex flex-col gap-1">
                                    {i > 0 && (
                                        <button onClick={() => moveItem(i, -1)} className="w-6 h-6 rounded-full bg-slate-900 border border-white/5 flex items-center justify-center text-slate-500 hover:text-white">
                                            <i className="fa-solid fa-chevron-up text-[10px]"></i>
                                        </button>
                                    )}
                                    {i < playback.queue.length - 1 && (
                                        <button onClick={() => moveItem(i, 1)} className="w-6 h-6 rounded-full bg-slate-900 border border-white/5 flex items-center justify-center text-slate-500 hover:text-white">
                                            <i className="fa-solid fa-chevron-down text-[10px]"></i>
                                        </button>
                                    )}
                                    <button onClick={() => removeItem(i)} className="w-6 h-6 rounded-full bg-slate-900 border border-white/5 flex items-center justify-center text-slate-500 hover:text-red-400">
                                        <i className="fa-solid fa-trash text-[10px]"></i>
                                    </button>
                                </div>
                            </div>
                        ))}
                    </div>
                )}
           </div>
       )}
    </div>
  );
};

export default Player;
