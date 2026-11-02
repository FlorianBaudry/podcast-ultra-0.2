async function run() {
  try {
    const res = await fetch('https://itunes.apple.com/lookup?id=1546899313&country=fr&entity=podcastEpisode&limit=5');
    const data = await res.json();
    console.log(`Results count: ${data.resultCount}`);
    
    // First result is podcast collection details
    if (data.results && data.results.length > 0) {
      console.log('--- PODCAST COLLECTION DETAILS ---');
      console.log(`Name: ${data.results[0].collectionName}`);
      console.log(`Release Date: ${data.results[0].releaseDate}`);
      
      console.log('\n--- EPISODES ---');
      for (const item of data.results.slice(1)) {
        console.log(`Track: ${item.trackName}`);
        console.log(`Release Date: ${item.releaseDate}`);
      }
    }
  } catch (e) {
    console.error(e);
  }
}

run();
