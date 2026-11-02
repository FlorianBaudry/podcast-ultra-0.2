
import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { LangCode, AccentColor, PlaybackState, Episode, RadioStation } from '../types';
import { translations } from '../translations';

interface SidebarProps {
  currentPath: string;
  lang: LangCode;
  accentColor: AccentColor;
  playback: PlaybackState;
  onToggle: () => void;
  audioRef: React.RefObject<HTMLAudioElement>;
  onTrackEnd: () => void;
}

const Sidebar: React.FC<SidebarProps> = ({ currentPath, lang, accentColor, playback, onToggle, audioRef, onTrackEnd }) => {
  const t = translations[lang];
  const [progress, setProgress] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);

  const links = [
    { name: t.discover, icon: 'fa-compass', path: '/' },
    { name: t.episodes_feed, icon: 'fa-clapperboard', path: '/episodes' },
    { name: t.audiobooks, icon: 'fa-book-open', path: '/audiobooks' },
    { name: t.radio, icon: 'fa-radio', path: '/radio' },
    { name: t.library || 'Bibliothèque', icon: 'fa-layer-group', path: '/library' },
  ];

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const updateProgress = () => {
      const cur = audio.currentTime;
      setCurrentTime(cur);
      setProgress((cur / audio.duration) * 100 || 0);
      setDuration(audio.duration || 0);
    };

    audio.addEventListener('timeupdate', updateProgress);
    return () => audio.removeEventListener('timeupdate', updateProgress);
  }, [audioRef, playback.currentTrack]);

  const formatTime = (time: number) => {
    if (isNaN(time)) return "0:00";
    const minutes = Math.floor(time / 60);
    const seconds = Math.floor(time % 60);
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  const isPodcast = playback.type === 'podcast';
  const track = playback.currentTrack;
  const artwork = track ? (isPodcast ? ((track as Episode).artworkUrl600 || (track as Episode).artworkUrl60) : (track as RadioStation).favicon) : null;
  const title = track ? (isPodcast ? (track as Episode).trackName : (track as RadioStation).name) : t.welcome;
  const subtitle = track ? (isPodcast ? ((track as Episode).artistName || (track as Episode).collectionName) : (track as RadioStation).country) : 'Prêt à écouter';

  return (
    <aside className="w-72 flex flex-col border-r border-white/5 bg-slate-950 hidden lg:flex h-full flex-shrink-0 relative z-20 shadow-2xl">
      <div className="p-6 pb-2">
        <div className="flex items-center gap-2 mb-4">
          <div className={`w-8 h-8 bg-${accentColor}-500 rounded-lg flex items-center justify-center shadow-lg shadow-${accentColor}-500/20`}>
            <i className="fa-solid fa-microphone-lines text-white"></i>
          </div>
          <h1 className="text-xl font-bold tracking-tight bg-gradient-to-r from-white to-slate-400 bg-clip-text text-transparent">Podcast Ultra</h1>
        </div>

        {/* INTEGRATED PLAYER SECTION */}
        <div className="bg-slate-900/50 rounded-3xl p-4 border border-white/5 shadow-inner mb-4 relative overflow-hidden group">
            <div className={`absolute inset-0 bg-gradient-to-br from-${accentColor}-500/10 to-transparent opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none`}></div>
            
            <div className="flex flex-col gap-4 relative z-10">
                <div className="aspect-square w-full max-h-32 bg-slate-800 rounded-2xl overflow-hidden shadow-lg relative mx-auto">
                    {artwork ? (
                        <img src={artwork} className="w-full h-full object-cover" alt="Cover" />
                    ) : (
                        <div className="w-full h-full flex items-center justify-center text-slate-700">
                            <i className="fa-solid fa-music text-4xl"></i>
                        </div>
                    )}
                    {/* Play Overlay */}
                    {track && (
                        <button 
                            onClick={onToggle}
                            className="absolute inset-0 bg-black/40 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity backdrop-blur-[2px]"
                        >
                            <div className="w-12 h-12 bg-white rounded-full flex items-center justify-center shadow-xl transform scale-90 group-hover:scale-100 transition-transform">
                                <i className={`fa-solid ${playback.isPlaying ? 'fa-pause' : 'fa-play'} text-black text-lg`}></i>
                            </div>
                        </button>
                    )}
                </div>

                <div>
                    <h3 className="text-sm font-bold text-white truncate leading-tight mb-1">{title}</h3>
                    <p className="text-xs text-slate-500 truncate">{subtitle}</p>
                </div>

                {track && (
                    <div className="space-y-2">
                         {isPodcast && (
                             <div className="flex items-center gap-2">
                                <span className="text-[9px] dark:text-slate-400 text-slate-500 w-6 text-right font-medium tabular-nums">{formatTime(currentTime)}</span>
                                <div className="flex-1 h-1 bg-slate-800 rounded-full overflow-hidden">
                                    <div className={`h-full bg-${accentColor}-500 rounded-full`} style={{ width: `${progress}%` }}></div>
                                </div>
                                <span className="text-[9px] dark:text-slate-400 text-slate-500 w-6 font-medium tabular-nums">{formatTime(duration)}</span>
                             </div>
                         )}
                         
                         <div className="flex items-center justify-between px-2 text-xs">
                            <button onClick={() => { if(audioRef.current) audioRef.current.currentTime -= 30; }} className="text-slate-500 hover:text-white transition-colors" title="-30s"><i className="fa-solid fa-rotate-left"></i></button>
                            <div className="flex items-center gap-3">
                               <button onClick={() => { if(audioRef.current) audioRef.current.currentTime = 0; }} className="text-slate-500 hover:text-white transition-colors" title="Recommencer"><i className="fa-solid fa-backward-step"></i></button>
                               <button 
                                   onClick={onToggle}
                                   className={`w-9 h-9 rounded-full bg-${accentColor}-600 text-white flex items-center justify-center shadow-lg shadow-${accentColor}-500/30 hover:scale-105 active:scale-95 transition-all outline-none`}
                               >
                                   <i className={`fa-solid ${playback.isPlaying ? 'fa-pause' : 'fa-play'}`}></i>
                               </button>
                               <button onClick={onTrackEnd} className="text-slate-500 hover:text-white transition-colors" title="Suivant"><i className="fa-solid fa-forward-step"></i></button>
                            </div>
                            <button onClick={() => { if(audioRef.current) audioRef.current.currentTime += 30; }} className="text-slate-500 hover:text-white transition-colors" title="+30s"><i className="fa-solid fa-rotate-right"></i></button>
                         </div>
                    </div>
                )}
            </div>
        </div>
      </div>

      <nav className="flex-1 space-y-1 overflow-y-auto no-scrollbar px-6 pb-6 pt-2">
        {links.map((link) => (
          <Link
            key={link.path}
            to={link.path}
            className={`flex items-center gap-3 px-3 py-3 rounded-2xl transition-all duration-200 group ${
              currentPath === link.path 
                ? `bg-${accentColor}-600/10 text-${accentColor}-400 font-bold` 
                : 'dark:text-slate-400 text-slate-500 hover:text-white hover:bg-white/5 font-medium'
            }`}
          >
            <i className={`fa-solid ${link.icon} text-lg w-6 text-center ${currentPath === link.path ? `text-${accentColor}-400` : 'text-slate-500 group-hover:text-white'}`}></i>
            <span className="text-sm">{link.name}</span>
          </Link>
        ))}
      </nav>


    </aside>
  );
};

export default Sidebar;
