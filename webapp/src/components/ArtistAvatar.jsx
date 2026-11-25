import { useState, useEffect } from 'react';
import { RetryImage } from './RetryImage';
import { resolveArtistAvatarForName } from '../services/albumArtService';
import { highResThumbnailURL } from '../utils/thumbnail';

// Lives in src/components to mirror mobile LTLibraryViewController artist rows:
// resolve a square 160px avatar from the artistAvatars store (searching YT
// Music on first sight), falling back to the first track's high-res art.
export const ArtistAvatar = ({ name, fallbackThumb, className }) => {
  const [avatar, setAvatar] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setAvatar(null);
    if (!name) return;
    resolveArtistAvatarForName(name).then(url => {
      if (!cancelled && url) setAvatar(url);
    });
    return () => { cancelled = true; };
  }, [name]);

  return (
    <RetryImage
      src={avatar || highResThumbnailURL(fallbackThumb)}
      alt={name}
      className={className}
      fallbackSrc={highResThumbnailURL(fallbackThumb)}
    />
  );
};