import React from 'react';
import { LangCode, AppSettings, LANGUAGES, AccentColor, Podcast, AppTheme } from '../types';
import { translations } from '../translations';


interface SettingsViewProps {
  langCode: LangCode;
  settings: AppSettings;
  onUpdateSettings: (s: Partial<AppSettings>) => void;
  currentLangCode: string;
  onUpdateLanguage: (code: string) => void;
  onImportPodcasts: (newPodcasts: Podcast[]) => void;
}

const SettingsView: React.FC<SettingsViewProps> = ({ langCode, settings, onUpdateSettings, currentLangCode, onUpdateLanguage, onImportPodcasts }) => {
  const t = translations[langCode];

  const speeds = [0.5, 0.8, 1, 1.2, 1.5, 1.8, 2, 2.5];
  const accentColors: AccentColor[] = ['indigo', 'blue', 'emerald', 'rose', 'violet', 'amber'];
  const themes: { id: AppTheme, label: string, icon: string, bg: string }[] = [
    { id: 'light', label: t.theme_light, icon: 'fa-sun', bg: 'bg-slate-200' },
    { id: 'dark', label: t.theme_dark, icon: 'fa-moon', bg: 'bg-slate-900' },
    { id: 'black', label: t.theme_black, icon: 'fa-lightbulb', bg: 'bg-black' },
  ];



  return (
    <div className="p-4 md:p-8 max-w-2xl mx-auto">
      <h1 className="text-3xl font-bold mb-8">{t.settings}</h1>
      
      <div className="space-y-6">
        <section className={`bg-slate-900/50 border border-white/5 rounded-3xl p-6`}>
          <h2 className={`text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 flex items-center gap-2`}>
            <i className={`fa-solid fa-language text-${settings.accentColor}-400`}></i>
            {t.language}
          </h2>
          <select 
            value={currentLangCode}
            onChange={(e) => onUpdateLanguage(e.target.value)}
            className="w-full bg-slate-800 border-none rounded-xl px-4 py-3 focus:ring-2 focus:ring-indigo-500 outline-none cursor-pointer text-sm font-bold text-white"
          >
            {LANGUAGES.map(l => (
              <option key={l.code} value={l.code}>{l.name}</option>
            ))}
          </select>
        </section>

        <section className="bg-slate-900/50 border border-white/5 rounded-3xl p-6">
          <h2 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <i className={`fa-solid fa-palette text-${settings.accentColor}-400`}></i>
            {t.accent_color}
          </h2>
          <div className="flex gap-3">
             {accentColors.map(color => (
                <button
                   key={color}
                   onClick={() => onUpdateSettings({ accentColor: color })}
                   className={`w-10 h-10 rounded-full bg-${color}-500 border-2 transition-transform hover:scale-110 ${settings.accentColor === color ? 'border-white scale-110 shadow-lg' : 'border-transparent opacity-60'}`}
                />
             ))}
          </div>
        </section>

        <section className="bg-slate-900/50 border border-white/5 rounded-3xl p-6">
          <h2 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <i className={`fa-solid fa-paint-roller text-${settings.accentColor}-400`}></i>
            {t.theme}
          </h2>
          <div className="grid grid-cols-3 gap-3">
             {themes.map(theme => (
                <button
                   key={theme.id}
                   onClick={() => onUpdateSettings({ theme: theme.id })}
                   className={`py-3 rounded-xl border flex flex-col items-center gap-2 transition-all ${settings.theme === theme.id ? `bg-white/10 border-${settings.accentColor}-500 text-white` : 'border-white/5 dark:text-slate-400 text-slate-500 hover:bg-white/5'}`}
                >
                   <div className={`w-8 h-8 rounded-full ${theme.bg} flex items-center justify-center border border-white/10 shadow-inner`}>
                      <i className={`fa-solid ${theme.icon} ${settings.theme === theme.id ? `text-${settings.accentColor}-400` : 'text-slate-500'}`}></i>
                   </div>
                   <span className="text-xs font-bold">{theme.label}</span>
                </button>
             ))}
          </div>
        </section>

        <section className="bg-slate-900/50 border border-white/5 rounded-3xl p-6">
          <h2 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <i className={`fa-solid fa-gauge-high text-${settings.accentColor}-400`}></i>
            {t.playback_speed}
          </h2>
          <div className="grid grid-cols-4 gap-2">
            {speeds.map(s => (
              <button
                key={s}
                onClick={() => onUpdateSettings({ playbackSpeed: s })}
                className={`py-2 rounded-xl text-sm font-bold transition-all ${
                  settings.playbackSpeed === s 
                  ? `bg-${settings.accentColor}-600 text-white shadow-lg shadow-${settings.accentColor}-500/20` 
                  : 'bg-slate-800 dark:text-slate-400 text-slate-500 hover:text-white'
                }`}
              >
                {s}x
              </button>
            ))}
          </div>
        </section>

        <section className="bg-slate-900/50 border border-white/5 rounded-3xl p-6">
          <h2 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <i className={`fa-solid fa-display text-${settings.accentColor}-400`}></i>
            {t.appearance}
          </h2>
          <div className="flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-white">{t.skip_intro}</span>
              <button
                onClick={() => onUpdateSettings({ skipIntro: !settings.skipIntro })}
                className={`w-12 h-6 rounded-full transition-all relative ${
                  settings.skipIntro ? `bg-${settings.accentColor}-600` : 'bg-slate-700'
                }`}
              >
                <div className={`absolute top-1 w-4 h-4 bg-white rounded-full transition-all ${
                  settings.skipIntro ? 'left-7' : 'left-1'
                }`} />
              </button>
            </div>
          </div>
        </section>

        <section className="bg-slate-900/50 border border-white/5 rounded-3xl p-6">
          <h2 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <i className={`fa-solid fa-clapperboard text-${settings.accentColor}-400`}></i>
            Flux d'épisodes
          </h2>
          <div className="flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <div>
                <span className="text-sm font-medium text-white block mb-1">Épisode le plus long par jour</span>
                <p className="text-[10px] dark:text-slate-400 text-slate-500 max-w-[240px] leading-tight">Supprime les doublons ou petits formats d'un même podcast le même jour.</p>
              </div>
              <button
                onClick={() => onUpdateSettings({ longestPerDayOnly: !settings.longestPerDayOnly })}
                className={`w-12 h-6 rounded-full transition-all relative ${
                  settings.longestPerDayOnly ? `bg-${settings.accentColor}-600` : 'bg-slate-700'
                }`}
              >
                <div className={`absolute top-1 w-4 h-4 bg-white rounded-full transition-all ${
                  settings.longestPerDayOnly ? 'left-7' : 'left-1'
                }`} />
              </button>
            </div>
          </div>
        </section>

        <section className="bg-slate-900/50 border border-white/5 rounded-3xl p-6">
          <h2 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <i className="fa-brands fa-spotify text-green-500"></i>
            Spotify
          </h2>
          <p className="text-sm dark:text-slate-400 text-slate-500 mb-4">{t.spotify_desc}</p>
          
          <div className="mb-4">
            <label className="text-xs font-bold text-slate-400 uppercase tracking-wider block mb-2">
              Spotify Client ID
            </label>
            <input 
              type="text" 
              value={settings.spotifyClientId || ''}
              onChange={(e) => onUpdateSettings({ spotifyClientId: e.target.value })}
              placeholder="Ex: 4a2b3cd4..." 
              className="w-full bg-slate-800 border-none rounded-xl px-4 py-3 focus:ring-2 focus:ring-indigo-500 outline-none text-sm font-semibold text-white" 
            />
            <p className="text-[10px] text-slate-500 mt-2 leading-tight">
              Pour connecter Spotify, créez une application sur le <a href="https://developer.spotify.com/dashboard" target="_blank" rel="noopener noreferrer" className="text-indigo-400 underline">Dashboard Spotify Developer</a>, configurez <strong>{window.location.origin}/</strong> comme <strong>Redirect URI</strong>, puis copiez le Client ID ci-dessus.
            </p>
          </div>

          <button
             id="spotify-btn"
             onClick={() => {
                const clientId = settings.spotifyClientId?.trim();
                if (!clientId) {
                  alert("Veuillez saisir votre Spotify Client ID ci-dessus pour lancer la connexion.");
                  return;
                }
                const redirectUri = window.location.origin + '/';
                const scope = 'user-library-read';
                const authUrl = `https://accounts.spotify.com/authorize?client_id=${encodeURIComponent(clientId)}&response_type=token&redirect_uri=${encodeURIComponent(redirectUri)}&scope=${encodeURIComponent(scope)}&state=spotify_import`;
                
                localStorage.setItem('podcast_ultra_spotify_import_pending', 'true');
                window.location.href = authUrl;
             }}
             className="w-full py-3 bg-green-500/10 hover:bg-green-500 text-green-500 hover:text-white border border-green-500/20 rounded-xl text-sm font-bold transition-all flex items-center justify-center gap-2"
          >
             <i className="fa-brands fa-spotify"></i>
             {t.spotify_connect}
          </button>
        </section>

        <section className="bg-slate-900/50 border border-white/5 rounded-3xl p-6">
          <h2 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <i className={`fa-solid fa-cloud-arrow-down text-${settings.accentColor}-400`}></i>
            Sauvegarde & Restauration
          </h2>
          <p className="text-sm dark:text-slate-400 text-slate-500 mb-4">Exportez vos réglages, favoris, options sélectionnées et historique pour éviter de tout perdre entre deux versions majeures.</p>
          <div className="flex gap-4">
             <button
               onClick={() => {
                 const safeParse = (key: string, fallback: any = null) => {
                   const raw = localStorage.getItem(key);
                   if (!raw) return fallback;
                   try { return JSON.parse(raw); } catch { return raw; }
                 };
                 const data = {
                   version: '0.2',
                   exportDate: new Date().toISOString(),
                   user: safeParse('voxstream_user'),
                   settings: safeParse('voxstream_settings', settings),
                   favs: safeParse('voxstream_favs_v2', []),
                   radios: safeParse('voxstream_fav_radios', []),
                   playlists: safeParse('voxstream_playlists', []),
                   lang: safeParse('voxstream_lang', LANGUAGES.find(l => l.code === currentLangCode) || LANGUAGES[0]),
                   played: safeParse('voxstream_played_ids', []),
                   positions: safeParse('voxstream_saved_positions', {}),
                   history: safeParse('voxstream_history', []),
                   dismissed: safeParse('podcast_ultra_dismissed', []),
                   lastTrendingCategory: localStorage.getItem('podcast_ultra_last_category') || 'All',
                   lastAudiobooksCategory: localStorage.getItem('podcast_ultra_audiobooks_category') || 'all'
                 };
                 const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
                 const url = URL.createObjectURL(blob);
                 const a = document.createElement('a');
                 a.href = url;
                 a.download = `podcast-ultra-backup-${new Date().toISOString().split('T')[0]}.json`;
                 a.click();
                 URL.revokeObjectURL(url);
               }}
               className={`flex-1 py-3 bg-${settings.accentColor}-600/10 hover:bg-${settings.accentColor}-600 text-${settings.accentColor}-400 hover:text-white border border-${settings.accentColor}-500/20 rounded-xl text-sm font-bold transition-all flex items-center justify-center gap-2`}
             >
               <i className="fa-solid fa-download"></i>
               Exporter
             </button>
             <label className={`flex-1 py-3 bg-slate-800 hover:bg-slate-700 text-white border border-white/5 hover:border-white/10 rounded-xl text-sm font-bold transition-all flex items-center justify-center gap-2 cursor-pointer`}>
               <i className="fa-solid fa-upload"></i>
               Importer
               <input 
                 type="file" 
                 accept=".json" 
                 className="hidden" 
                 onChange={(e) => {
                   const file = e.target.files?.[0];
                   if (!file) return;
                   const reader = new FileReader();
                   reader.onload = (event) => {
                     try {
                       const data = JSON.parse(event.target?.result as string);
                       const toStorageString = (val: any) => typeof val === 'string' ? val : JSON.stringify(val);
                       if (data && (data.settings !== undefined || data.favs !== undefined || data.favorites !== undefined)) {
                         if (data.user != null) localStorage.setItem('voxstream_user', toStorageString(data.user));
                         if (data.settings != null) localStorage.setItem('voxstream_settings', toStorageString(data.settings));
                         const favs = data.favs ?? data.favorites ?? data.favoritePodcasts;
                         if (favs != null) localStorage.setItem('voxstream_favs_v2', toStorageString(favs));
                         const radios = data.radios ?? data.favoriteRadios;
                         if (radios != null) localStorage.setItem('voxstream_fav_radios', toStorageString(radios));
                         if (data.playlists != null) localStorage.setItem('voxstream_playlists', toStorageString(data.playlists));
                         const langVal = data.lang ?? data.language;
                         if (langVal != null) {
                           if (typeof langVal === 'string' && !langVal.trim().startsWith('{')) {
                             const found = LANGUAGES.find(l => l.code === langVal);
                             if (found) localStorage.setItem('voxstream_lang', JSON.stringify(found));
                           } else {
                             localStorage.setItem('voxstream_lang', toStorageString(langVal));
                           }
                         }
                         const played = data.played ?? data.playedEpisodeIds;
                         if (played != null) localStorage.setItem('voxstream_played_ids', toStorageString(played));
                         const positions = data.positions ?? data.savedPositions;
                         if (positions != null) localStorage.setItem('voxstream_saved_positions', toStorageString(positions));
                         if (data.history != null) localStorage.setItem('voxstream_history', toStorageString(data.history));
                         const dismissed = data.dismissed ?? data.dismissedEpisodeIds;
                         if (dismissed != null) localStorage.setItem('podcast_ultra_dismissed', toStorageString(dismissed));
                         if (typeof data.lastTrendingCategory === 'string') {
                           localStorage.setItem('podcast_ultra_last_category', data.lastTrendingCategory);
                         }
                         if (typeof data.lastAudiobooksCategory === 'string') {
                           localStorage.setItem('podcast_ultra_audiobooks_category', data.lastAudiobooksCategory);
                         }
                         alert("Restauration réussie ! L'application va redémarrer.");
                         window.location.reload();
                       } else {
                         alert("Fichier de sauvegarde invalide.");
                       }
                     } catch(err) {
                       alert("Erreur lors de la restauration.");
                     }
                   };
                   reader.readAsText(file);
                 }}
               />
             </label>
          </div>
        </section>

        <section className="bg-slate-900/50 border border-white/5 rounded-3xl p-6">
          <h2 className="text-xs font-bold text-slate-500 uppercase tracking-widest mb-4 flex items-center gap-2">
            <i className="fa-solid fa-triangle-exclamation text-red-400"></i>
            Dangerous Zone
          </h2>
          <button
            onClick={() => {
              if (confirm('Voulez-vous vraiment effacer toutes les données ?')) {
                localStorage.clear();
                window.location.reload();
              }
            }}
            className="w-full py-3 bg-red-500/10 hover:bg-red-500 text-red-500 hover:text-white border border-red-500/20 rounded-xl text-sm font-bold transition-all"
          >
            {t.clear_cache}
          </button>
        </section>
      </div>
    </div>
  );
};

export default SettingsView;
