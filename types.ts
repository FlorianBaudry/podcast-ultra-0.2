
export interface Podcast {
  collectionId: number;
  artistName: string;
  collectionName: string;
  artworkUrl100: string;
  artworkUrl600: string;
  feedUrl: string;
  genres: string[];
  genreIds?: string[];
  primaryGenreName: string;
  releaseDate: string;
  country?: string;
  description?: string;
  source?: 'itunes' | 'librivox' | 'openlibrary' | 'archive' | 'litteratureaudio' | 'storynory';
}

export interface Episode {
  trackId: number;
  trackName: string;
  description: string;
  releaseDate: string;
  previewUrl: string;
  trackTimeMillis: number;
  artworkUrl60: string;
  artworkUrl160?: string;
  artworkUrl600?: string;
  collectionName: string;
  collectionId?: number;
  artistName?: string;
}

export interface RadioStation {
  id: string;
  name: string;
  url: string;
  favicon: string;
  tags: string;
  country: string;
  language?: string;
  clickcount?: number;
}

export interface Playlist {
  id: string;
  name: string;
  episodes: Episode[];
}

export interface User {
  id: string;
  name: string;
  email: string;
  avatar?: string;
  isGuest?: boolean;
}

export type AccentColor = 'indigo' | 'blue' | 'emerald' | 'rose' | 'violet' | 'amber';
export type AppTheme = 'light' | 'dark' | 'black';

export interface AppSettings {
  playbackSpeed: number;
  skipIntro: boolean;
  accentColor: AccentColor;
  theme: AppTheme;
  deleteAfterListening?: boolean;
  longestPerDayOnly?: boolean;
  spotifyClientId?: string;
  autoDownloadLatest?: boolean;
}

export interface PlaybackState {
  currentTrack: Episode | RadioStation | null;
  isPlaying: boolean;
  type: 'podcast' | 'radio';
  queue: Episode[];
  speed: number;
}

export const LANGUAGES = [
  { code: 'en', name: 'English', itunes: 'us', radioSearch: 'english', countryCode: 'US' },
  { code: 'fr', name: 'Français', itunes: 'fr', radioSearch: 'french', countryCode: 'FR' },
  { code: 'fr-BE', name: 'Français (Belgique)', itunes: 'be', radioSearch: 'french', countryCode: 'BE' },
  { code: 'es', name: 'Español', itunes: 'es', radioSearch: 'spanish', countryCode: 'ES' },
  { code: 'de', name: 'Deutsch', itunes: 'de', radioSearch: 'german', countryCode: 'DE' },
  { code: 'it', name: 'Italiano', itunes: 'it', radioSearch: 'italian', countryCode: 'IT' },
  { code: 'pt', name: 'Português', itunes: 'pt', radioSearch: 'portuguese', countryCode: 'PT' },
  { code: 'ja', name: '日本語', itunes: 'jp', radioSearch: 'japanese', countryCode: 'JP' },
];

export const CATEGORIES = [
  'All', 'News', 'Comedy', 'Technology', 'Business', 'Society & Culture', 'True Crime', 'Health', 'Education', 'History', 'Music', 'Science', 'Sports'
];

export type LangCode = 'en' | 'fr' | 'es' | 'de' | 'it' | 'pt' | 'ja';
