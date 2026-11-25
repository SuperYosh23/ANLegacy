import { useState, useEffect, useCallback } from 'react';
import { Play, Clock, ListMusic, ChevronRight, Music } from 'lucide-react';
import { usePlayer } from '../context/PlayerContext';
import { useNavigate } from '../context/NavigationContext';
import { storage } from '../utils/storage';
import { ArtImage } from './ArtImage';

const MAX_RECENTS = 20;

function artistName(song) {
  return song.channelTitle || song.artists?.[0]?.name || 'Unknown Artist';
}

function playlistThumb(playlist) {
  return playlist.customThumbnail || playlist.songs?.[0]?.thumbnail || null;
}

export const Recommendations = () => {
  const [recents, setRecents] = useState([]);
  const [playlists, setPlaylists] = useState([]);
  const [totalSongs, setTotalSongs] = useState(0);
  const { playSong } = usePlayer();
  const { navigate } = useNavigate();

  const refresh = useCallback(() => {
    setRecents(storage.getListeningHistory());
    setPlaylists(storage.getPlaylists());
    setTotalSongs(storage.getTotalSongs());
  }, []);

  useEffect(() => {
    refresh();
    window.addEventListener('history-changed', refresh);
    window.addEventListener('playlists-changed', refresh);
    return () => {
      window.removeEventListener('history-changed', refresh);
      window.removeEventListener('playlists-changed', refresh);
    };
  }, [refresh]);

  const handlePlay = (song) => {
    playSong(song, [song]);
  };

  const handleOpenPlaylist = (playlist) => {
    navigate({ type: 'playlist', params: { id: playlist.id } });
  };

  const hasContent = recents.length > 0 || playlists.length > 0;

  return (
    <div className="p-6 animate-fadeIn">
      {/* Banner greeting */}
      <div className="relative rounded-3xl overflow-hidden mb-8 bg-gradient-to-br from-primary-container/40 via-surface-container to-secondary-container/30 border border-outline-variant/20">
        <div className="absolute inset-0 bg-gradient-to-br from-primary/5 to-transparent" />
        <div className="relative p-8">
          <h1 className="text-3xl font-bold text-on-surface">Welcome back.</h1>
          <p className="text-on-surface-variant mt-1">
            You've listened to {totalSongs} song{totalSongs === 1 ? '' : 's'}.
          </p>
        </div>
      </div>

      {hasContent ? (
        <>
          {/* Recently Played — horizontal strip */}
          {recents.length > 0 && (
            <div className="mb-8">
              <h2 className="text-xl font-bold text-on-surface flex items-center gap-2 mb-4">
                <Clock size={22} className="text-primary" />
                Recently Played
              </h2>
              <div className="flex gap-3 overflow-x-auto pb-2">
                {recents.slice(0, MAX_RECENTS).map((song, index) => (
                  <button
                    key={song.videoId}
                    onClick={() => handlePlay(song)}
                    className="w-36 shrink-0 group text-left animate-slideUp"
                    style={{ animationDelay: `${index * 0.03}s`, animationFillMode: 'backwards' }}
                  >
                    {/* h-36 rather than aspect-square: aspect-ratio arrived in
                        Safari 15, and on iOS 9 this box would have no height at
                        all and the artwork inside it would collapse to nothing.
                        The width is w-36, so an explicit height keeps it square. */}
                    <div className="relative w-36 h-36 rounded-2xl overflow-hidden bg-surface-container-high shadow-md">
                      <ArtImage
                        src={song.thumbnail}
                        alt={song.title}
                        className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                      />
                      <div className="absolute inset-0 bg-black/20 opacity-0 group-hover:opacity-100 transition-opacity flex items-end justify-center p-2">
                        <span className="bg-primary text-on-primary p-2.5 rounded-full shadow-lg">
                          <Play size={18} fill="currentColor" />
                        </span>
                      </div>
                    </div>
                    <p className="mt-2 text-sm font-semibold text-on-surface line-clamp-2 leading-tight h-10">
                      {song.title}
                    </p>
                    <p className="text-xs text-on-surface-variant truncate mt-0.5">
                      {artistName(song)}
                    </p>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Your Playlists */}
          {playlists.length > 0 && (
            <div className="mb-8">
              <h2 className="text-xl font-bold text-on-surface flex items-center gap-2 mb-4">
                <ListMusic size={22} className="text-primary" />
                Your Playlists
              </h2>
              <div className="bg-surface-container/30 rounded-2xl divide-y divide-outline-variant/20 overflow-hidden">
                {playlists.map((playlist) => {
                  const thumb = playlistThumb(playlist);
                  return (
                    <button
                      key={playlist.id}
                      onClick={() => handleOpenPlaylist(playlist)}
                      className="w-full flex items-center gap-3 p-2.5 hover:bg-surface-container-high/50 transition-all text-left group"
                    >
                      {thumb ? (
                        <ArtImage
                          src={thumb}
                          alt=""
                          className="w-14 h-14 rounded-xl object-cover shadow-md shrink-0 group-hover:scale-105 transition-transform duration-300"
                        />
                      ) : (
                        <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-primary to-primary-container flex items-center justify-center shrink-0">
                          <Music size={22} className="text-on-surface" />
                        </div>
                      )}
                      <div className="flex-1 min-w-0">
                        <p className="text-on-surface font-medium truncate">{playlist.name}</p>
                        <p className="text-xs text-on-surface-variant">
                          {playlist.songs.length} track{playlist.songs.length === 1 ? '' : 's'}
                        </p>
                      </div>
                      <ChevronRight size={18} className="text-outline shrink-0" />
                    </button>
                  );
                })}
              </div>
            </div>
          )}
        </>
      ) : (
        <div className="py-20 text-center">
          <p className="text-on-surface-variant">
            Nothing here yet.
            <br />
            Play a song and create playlists to see them.
          </p>
        </div>
      )}
    </div>
  );
};