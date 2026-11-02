
import React, { useEffect, useState } from 'react';
import { getAudiobooks, getPodcastEpisodes, categorizePodcast } from '../services/api';
import { Podcast, LangCode, Episode, AccentColor } from '../types';
import { translations } from '../translations';

interface AudiobooksViewProps {
  language: { code: string, itunes: string };
  langCode: LangCode;
  onSelectPodcast: (podcast: Podcast) => void;
  favoritePodcasts: Podcast[];
  onToggleFavorite: (podcast: Podcast) => void;
  accentColor: AccentColor;
}

const AudiobooksView: React.FC<AudiobooksViewProps> = ({ language, langCode, onSelectPodcast, favoritePodcasts, onToggleFavorite, accentColor }) => {
  const [books, setBooks] = useState<Podcast[] | null>(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('podcast_ultra_cached_audiobooks');
      return saved ? JSON.parse(saved) : null;
    }
    return null;
  });
  const [loading, setLoading] = useState(() => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('podcast_ultra_cached_audiobooks');
      const parsed = saved ? JSON.parse(saved) : null;
      return parsed === null;
    }
    return true;
  });
  const [activeCategory, setActiveCategory] = useState(() => localStorage.getItem('podcast_ultra_audiobooks_category') || 'all');
  const [refreshTrigger, setRefreshTrigger] = useState(0);
  const [bookDurations, setBookDurations] = useState<Record<number, number>>({});
  const t = translations[langCode];
  const bookCats = t.book_cats as Record<string, string>;
  const categories = Object.keys(bookCats);

  const favoriteBooks = favoritePodcasts.filter(p => {
    const g = p.genres?.map(x => x.toLowerCase()).join(' ') || '';
    return ['audiobook', 'fiction', 'book', 'livre', 'roman', 'serial'].some(kw => g.includes(kw));
  });

  useEffect(() => {
    const lastCategory = localStorage.getItem('podcast_ultra_audiobooks_category_last');
    const categoryChanged = lastCategory !== activeCategory;

    // Fetch only if cache is empty, category changed, or manual refresh requested
    if (refreshTrigger === 0 && !categoryChanged && books !== null) {
      return;
    }

    const load = async () => {
      setLoading(true);
      const data = await getAudiobooks(language.itunes, activeCategory, refreshTrigger > 0);
      setBooks(data);
      setLoading(false);
      if (typeof window !== 'undefined') {
        localStorage.setItem('podcast_ultra_cached_audiobooks', JSON.stringify(data));
        localStorage.setItem('podcast_ultra_audiobooks_category_last', activeCategory);
      }

      // Start fetching durations in background for filtering
      data.forEach(async (book) => {
        if (!bookDurations[book.collectionId]) {
           try {
             const episodes = await getPodcastEpisodes(book.collectionId, undefined, book.feedUrl);
             const totalMs = episodes.reduce((acc, ep) => acc + (ep.trackTimeMillis || 0), 0);
             setBookDurations(prev => ({ ...prev, [book.collectionId]: totalMs }));
           } catch (e) {}
        }
      });
    };
    load();
    localStorage.setItem('podcast_ultra_audiobooks_category', activeCategory);
  }, [language, activeCategory, refreshTrigger]);

  const filteredBooks = (books || []).filter(book => {
    const duration = bookDurations[book.collectionId];
    if (duration === undefined) return true; // Show while loading duration
    return duration >= 1800000; // 30 minutes
  });

  const filteredFavorites = favoriteBooks.filter(book => {
    const duration = bookDurations[book.collectionId];
    if (duration === undefined) return true;
    return duration >= 1800000;
  });

  const renderBookGrid = (list: Podcast[]) => (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4 md:gap-6">
      {list.map((book) => {
        const isFav = favoritePodcasts.some(f => f.collectionId === book.collectionId);
        return (
          <div key={book.collectionId} className="bg-slate-900/40 p-3 md:p-4 rounded-3xl border border-white/5 hover:bg-slate-800/60 transition-all cursor-pointer group hover:border-indigo-500/20 shadow-lg relative">
            <div onClick={() => onSelectPodcast(book)} className="relative mb-3 aspect-[2/3] overflow-hidden rounded-2xl shadow-xl">
              <img src={book.artworkUrl600 || book.artworkUrl100} alt={book.collectionName} className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700" />
              <div className="absolute top-2 right-2 px-2 py-1 bg-black/60 backdrop-blur-md rounded-lg text-[9px] font-black text-white border border-white/10 uppercase tracking-tighter shadow-lg">
                {book.source === 'librivox' ? 'LibriVox' : 
                 book.source === 'archive' ? 'Archive' :
                 book.source === 'storynory' ? 'Storynory' : 
                 book.source === 'litteratureaudio' ? 'Litterature' : 'Livre Audio'}
              </div>
              <div className="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                <div className="w-12 h-12 bg-indigo-500 rounded-full flex items-center justify-center text-white transform scale-75 group-hover:scale-100 transition-transform shadow-2xl"><i className="fa-solid fa-play text-lg"></i></div>
              </div>
            </div>
            <button 
              onClick={(e) => { e.stopPropagation(); onToggleFavorite(book); }}
              className={`absolute bottom-16 right-6 w-10 h-10 rounded-full border border-white/10 flex items-center justify-center shadow-xl md:opacity-0 group-hover:opacity-100 transition-opacity z-10 ${isFav ? 'bg-red-500 text-white opacity-100' : 'bg-slate-800 dark:text-slate-400 text-slate-500 hover:text-white'}`}
            >
              <i className={`${isFav ? 'fa-solid' : 'fa-regular'} fa-heart`}></i>
            </button>
            <div onClick={() => onSelectPodcast(book)}>
              <h3 className="font-bold text-white text-sm md:text-base mb-1 truncate leading-tight group-hover:text-indigo-400 transition-colors">{book.collectionName}</h3>
              <p className="text-[10px] md:text-xs dark:text-slate-400 text-slate-500 truncate font-medium uppercase tracking-tight">{book.artistName}</p>
            </div>
          </div>
        );
      })}
    </div>
  );

  return (
    <div className="p-4 md:p-8">
        <div className="mb-8 flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div className="flex flex-wrap items-center gap-3">
            <button
              onClick={() => setRefreshTrigger(t => t + 1)}
              title={langCode === 'fr' ? 'Rafraîchir les livres' : 'Refresh books'}
              className={`flex items-center gap-2 px-4 py-2.5 rounded-xl text-xs font-bold bg-slate-900 border border-white/5 text-slate-400 hover:text-white hover:border-${accentColor}-500/30 transition-all w-fit`}
            >
              <i className={`fa-solid fa-arrows-rotate ${loading ? 'animate-spin' : ''}`}></i>
              <span className="hidden sm:inline">{langCode === 'fr' ? 'Rafraîchir' : 'Refresh'}</span>
            </button>
          </div>
          
          {/* Category Picklist */}
          <select 
             value={activeCategory} 
             onChange={(e) => setActiveCategory(e.target.value)} 
             className={`bg-slate-900 border border-white/10 rounded-xl px-4 py-2 text-xs font-bold text-slate-300 outline-none focus:ring-2 focus:ring-${accentColor}-500 w-full md:w-auto shadow-lg`}
          >
             {categories.map(cat => (
               <option key={cat} value={cat}>{bookCats[cat]}</option>
             ))}
          </select>
       </div>

      {favoriteBooks.length > 0 && activeCategory === 'all' && (
        <section className="mb-14 animate-in fade-in slide-in-from-top-4 duration-500">
           <h2 className="text-xl font-bold mb-6 flex items-center gap-2"><i className="fa-solid fa-heart text-red-500"></i> Vos Favoris</h2>
           {renderBookGrid(filteredFavorites)}
           <div className="h-px bg-white/5 my-12"></div>
        </section>
      )}

      {loading && (!books || books.length === 0) ? (
        <div className="flex justify-center py-20">
          <div className={`animate-spin w-10 h-10 border-4 border-${accentColor}-500 border-t-transparent rounded-full`}></div>
        </div>
      ) : (
        <div className="space-y-14">
           {activeCategory !== 'all' ? (
             <section>
                <h2 className="text-xl font-bold mb-6 flex items-center gap-2">
                  <i className="fa-solid fa-fire text-orange-500"></i> 
                  {bookCats[activeCategory]}
                </h2>
                {renderBookGrid(filteredBooks.filter(b => !favoriteBooks.some(fb => fb.collectionId === b.collectionId)))}
             </section>
           ) : (
             // Grouped sections for 'all' view
             categories.filter(c => c !== 'all').map(catKey => {
                const catBooks = filteredBooks.filter(b => categorizePodcast(b) === catKey && !favoriteBooks.some(fb => fb.collectionId === b.collectionId));
                if (catBooks.length === 0) return null;
                
                return (
                  <section key={catKey} className="animate-in fade-in slide-in-from-bottom-4 duration-700">
                    <h2 className="text-xl font-bold mb-6 flex items-center gap-2">
                      <i className={`fa-solid ${
                        catKey === 'fiction' ? 'fa-book' :
                        catKey === 'thriller' ? 'fa-user-secret' :
                        catKey === 'scifi' ? 'fa-rocket' :
                        catKey === 'history' ? 'fa-landmark' :
                        catKey === 'kids' ? 'fa-child' :
                        catKey === 'growth' ? 'fa-leaf' : 'fa-palette'
                      } text-indigo-400`}></i>
                      {bookCats[catKey]}
                    </h2>
                    {renderBookGrid(catBooks.slice(0, 10))}
                    <div className="h-px bg-white/5 mt-12 mb-4"></div>
                  </section>
                );
             })
           )}
        </div>
      )}
    </div>
  );
};

export default AudiobooksView;
