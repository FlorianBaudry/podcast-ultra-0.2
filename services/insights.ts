// Generates a short insightful blurb for a podcast using a static template instead of AI
export const getPodcastInsight = async (name: string, artist: string, genres: string[], language: string = 'English') => {
  try {
    const genreText = genres && genres.length > 0 ? genres[0] : 'podcast';
    
    if (language.toLowerCase().startsWith('fr')) {
      return `Un podcast ${genreText} par ${artist}.`;
    }
    return `A ${genreText} podcast by ${artist}.`;
  } catch (error) {
    return "";
  }
};
