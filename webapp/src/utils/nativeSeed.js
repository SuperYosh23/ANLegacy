// Seeds the web app's own local storage from the phone's library.
//
// The web app keeps its playlists and library in localStorage, which on the
// phone starts empty. Without this the Library and Playlists tabs show
// nothing at all, even though the phone has four playlists and forty-odd
// tracks.
//
// The data is copied in rather than fetched on demand because the web app's
// storage API is synchronous - it is read during render - and making it async
// would mean changing every caller. One write at start-up is simpler and keeps
// the web app's own code untouched.
//
// Only the phone's copy does this. The desktop app keeps using its own
// localStorage, which is where its playlists live.
export const seedFromNativeLibrary = async () => {
  const isPhone = (() => {
    try {
      return new URLSearchParams(window.location.search).get('mobile') === '1';
    } catch {
      return false;
    }
  })();
  if (!isPhone) return false;

  try {
    const res = await fetch('/api/local/playlists');
    const data = await res.json();
    const playlists = data && data.playlists;
    if (!Array.isArray(playlists) || !playlists.length) return false;

    // The phone's playlists are the ones the listener actually made, so they
    // replace whatever the browser had.
    window.localStorage.setItem('ym_playlists', JSON.stringify(playlists));

    // The app keeps a count of the songs in the library for its stats screen.
    const songCount = playlists.reduce((total, p) => total + ((p.songs || []).length), 0);
    if (songCount) {
      window.localStorage.setItem('ym_total_songs', String(songCount));
    }
    return true;
  } catch {
    return false;
  }
};
