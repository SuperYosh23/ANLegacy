import { useState, useEffect } from 'react';
import { Play, Music, Search as SearchIcon } from 'lucide-react';
import { useNavigate } from '../context/NavigationContext';
import { usePlayer } from '../context/PlayerContext';
import { ArtImage } from './ArtImage';

// The phone's Home screen, matching the native app: recently played across the
// top, then the playlists.
//
// The data comes from the phone's own store over /api/local, not from the
// browser's localStorage, so this is the same library and the same playlists the
// native app shows.
export const MobileHome = ({ onOpenSearch }) => {
  const [recents, setRecents] = useState([]);
  const [playlists, setPlaylists] = useState([]);
  const [loading, setLoading] = useState(true);
  const { navigate } = useNavigate();
  const { playSong, setQueueSongs } = usePlayer();

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        const [recentRes, playlistRes] = await Promise.all([
          fetch('/api/local/recents').then(r => r.json()).catch(() => ({ tracks: [] })),
          fetch('/api/local/playlists').then(r => r.json()).catch(() => ({ playlists: [] })),
        ]);
        if (cancelled) return;
        setRecents(recentRes?.tracks || []);
        setPlaylists(playlistRes?.playlists || []);
      } catch {
        if (!cancelled) { setRecents([]); setPlaylists([]); }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    load();
    return () => { cancelled = true; };
  }, []);

  const openPlaylist = (playlist) => {
    navigate({ type: 'playlist', params: { id: playlist.id, title: playlist.name } });
  };

  const playAll = (playlist) => {
    const songs = (playlist.tracks || []).map(toSong);
    if (!songs.length) return;
    playSong(songs[0], songs);
  };

  return (
    <div className="pb-4">
      {/* Recently played */}
      <section className="pt-3">
        <div className="flex items-center justify-between px-4 mb-2">
          <h2 className="text-sm font-semibold text-on-surface-variant">Recently played</h2>
          <button
            onClick={onOpenSearch}
            className="text-xs font-medium text-primary flex items-center gap-1"
          >
            <SearchIcon size={14} /> Search
          </button>
        </div>
        {recents.length === 0 ? (
          <p className="px-4 text-sm text-on-surface-variant">
            {loading ? 'Loading…' : 'Nothing played yet.'}
          </p>
        ) : (
          <div className="flex gap-3 overflow-x-auto px-4 pb-1" style={{ WebkitOverflowScrolling: 'touch' }}>
            {recents.map((track) => (
              <button
                key={track.videoId}
                onClick={() => { const s = toSong(track); playSong(s, [s]); }}
                className="shrink-0 w-[7.5rem] text-left"
              >
                <div className="w-[7.5rem] h-[7.5rem] rounded-2xl overflow-hidden bg-surface-container">
                  <ArtImage
                    src={thumbUrl(track)}
                    alt={track.title}
                    className="w-full h-full object-cover"
                  />
                </div>
                <div className="mt-1.5 text-xs font-medium truncate">{track.title}</div>
                <div className="text-[11px] text-on-surface-variant truncate">
                  {track.channelTitle || ''}
                </div>
              </button>
            ))}
          </div>
        )}
      </section>

      {/* Playlists */}
      <section className="mt-4">
        <h2 className="px-4 mb-2 text-sm font-semibold text-on-surface-variant">Playlists</h2>
        {playlists.length === 0 ? (
          <p className="px-4 text-sm text-on-surface-variant">
            {loading ? 'Loading…' : 'No playlists yet.'}
          </p>
        ) : (
          <ul>
            {playlists.map((playlist) => (
              <li key={playlist.id} className="flex items-center gap-3 px-4 py-2 active:bg-surface-container-high">
                <button
                  onClick={() => openPlaylist(playlist)}
                  className="flex items-center gap-3 flex-1 min-w-0 text-left"
                >
                  <div className="w-11 h-11 rounded-xl overflow-hidden bg-surface-container shrink-0 flex items-center justify-center">
                    {playlist.cover?.url ? (
                      <ArtImage src={playlist.cover.url} alt={playlist.name} className="w-full h-full object-cover" rounded={false} />
                    ) : (
                      <Music size={20} className="text-on-surface-variant" />
                    )}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-medium truncate">{playlist.name}</div>
                    <div className="text-xs text-on-surface-variant">
                      {(playlist.tracks || []).length} song{(playlist.tracks || []).length === 1 ? '' : 's'}
                    </div>
                  </div>
                </button>
                <button
                  onClick={() => playAll(playlist)}
                  className="h-9 w-9 rounded-full flex items-center justify-center text-primary hover:bg-surface-container-high"
                  aria-label={`Play ${playlist.name}`}
                >
                  <Play size={18} />
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
};

const thumbUrl = (track) => {
  const thumbs = track.thumbnails || [];
  if (thumbs.length) return thumbs[thumbs.length - 1].url;
  return '';
};

// The web app's own track shape, which the player expects.
const toSong = (track) => ({
  videoId: track.videoId || '',
  title: track.title || '',
  artists: (track.artists || []).map(a => ({ name: a.name, artistId: a.id || '' })),
  channelTitle: track.channelTitle || '',
  channelId: track.channelId || '',
  thumbnail: thumbUrl(track),
  duration: track.duration_seconds || 0,
  album: track.album?.name || '',
  albumId: track.album?.id || '',
});
