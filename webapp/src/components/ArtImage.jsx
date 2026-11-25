import { useState, useEffect } from 'react';
import { RetryImage } from './RetryImage';
import { loadArtwork } from '../services/albumArtService';
import { highResThumbnailURL } from '../utils/thumbnail';

// Drop-in for RetryImage on track/playlist artwork. Runs the ported mobile
// image pipeline (high-res resolution + border-trim + IndexedDB cache) and
// renders the trimmed result, upgrading to the raw high-res URL immediately so
// the image paints before the pipeline resolves. Falls back to RetryImage's
// retry/fallback behavior when there is no thumbnail at all.
export const ArtImage = ({ src, alt, className, fallbackSrc, onError, ...props }) => {
  const [processed, setProcessed] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setProcessed(null);
    if (!src) return;
    loadArtwork(src).then(dataUrl => {
      if (!cancelled && dataUrl) setProcessed(dataUrl);
    });
    return () => { cancelled = true; };
  }, [src]);

  return (
    <RetryImage
      src={processed || highResThumbnailURL(src)}
      alt={alt}
      className={className}
      fallbackSrc={fallbackSrc}
      onError={onError}
      {...props}
    />
  );
};