import { useState, useEffect } from 'react';
import { loadArtwork, blurredImageFromImage } from '../services/albumArtService';
import { highResThumbnailURL } from '../utils/thumbnail';

// Port of the mobile player artwork flow (LTPlayerViewController.refreshTrack +
// setArtworkImage): resolve high-res art, load/trim/cache it, and derive a
// blurred variant for the artwork background (LTGraphics.blurredImageFromImage).
// Falls back to the raw high-res URL when the pipeline can't decode, so the
// <img> can still load it directly.
export function useTrackArtwork(song) {
  const [artwork, setArtwork] = useState(() => song?.thumbnail ? highResThumbnailURL(song.thumbnail) : '');
  const [blurred, setBlurred] = useState(null);

  useEffect(() => {
    const raw = song?.thumbnail;
    if (!raw) { setArtwork(''); setBlurred(null); return; }
    let cancelled = false;
    const fallbackURL = highResThumbnailURL(raw);
    setArtwork(current => current || fallbackURL);
    loadArtwork(raw).then(dataUrl => {
      if (cancelled || !dataUrl) return;
      setArtwork(dataUrl);
      blurredImageFromImage(dataUrl).then(b => {
        if (!cancelled && b) setBlurred(b);
      });
    });
    return () => { cancelled = true; };
  }, [song?.videoId, song?.thumbnail]);

  return { artwork, blurred, rawURL: song?.thumbnail ? highResThumbnailURL(song.thumbnail) : '' };
}

// Port of the mobile queue background (LTQueueViewController.loadBackgroundArt):
// blurred artwork behind the now-playing track with a scrim.
export function useBlurredArtwork(song, enabled = true) {
  const { blurred } = useTrackArtwork(enabled ? song : null);
  return blurred;
}