import { useState, useEffect } from 'react';
import { apiService } from '../services/apiService';

export function useAlbumArt(song) {
  const [fallback, setFallback] = useState(null);

  useEffect(() => {
    if (!song) { setFallback(null); return; }
    const title = song.album || song.title;
    const artist = song.channelTitle || '';
    if (!title && !artist) { setFallback(null); return; }
    let cancelled = false;
    apiService.getAlbumArt(title, artist).then(url => {
      if (!cancelled) setFallback(url);
    });
    return () => { cancelled = true; };
  }, [song]);

  return fallback;
}
