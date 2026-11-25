import { useState, useEffect } from 'react';
import { ArrowLeft, Music, Play, Shuffle, Plus } from 'lucide-react';
import { usePlayer } from '../context/PlayerContext';
import { useNavigate } from '../context/NavigationContext';
import { youtubeScraperService } from '../services/youtubeScraper';
import { PlaylistPickerModal } from './PlaylistPickerModal';
import { LoadingIndicator } from './LoadingIndicator';
import { ArtImage } from './ArtImage';
import { ArtistAvatar } from './ArtistAvatar';

export const ArtistPage = () => {
  const { subPage, navigate, navigateBack } = useNavigate();
  const { playSong, setQueueSongs } = usePlayer();
  const [songs, setSongs] = useState([]);
  const [albums, setAlbums] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [pickerSong, setPickerSong] = useState(null);

  const artist = subPage?.params;

  useEffect(() => {
    if (!artist?.name) {
      setLoading(false);
      return;
    }
    let cancelled = false;
    setLoading(true);
    setError('');
    Promise.all([
      youtubeScraperService.search(artist.name, 20),
      youtubeScraperService.searchAlbums(artist.name),
    ]).then(([songResults, albumResults]) => {
      if (!cancelled) {
        setSongs(songResults);
        setAlbums(albumResults);
      }
    }).catch(err => {
      if (!cancelled) { console.error('Failed to load artist data:', err); setError('Could not reach the music backend.'); }
    }).finally(() => {
      if (!cancelled) setLoading(false);
    });
    return () => { cancelled = true; };
  }, [artist?.name]);

  const handlePlaySong = (song) => {
    playSong(song, songs);
  };

  const handlePlayAll = () => {
    if (songs.length > 0) setQueueSongs(songs, 0);
  };

  const handleShuffle = () => {
    if (songs.length > 0) {
      const shuffled = [...songs].sort(() => Math.random() - 0.5);
      setQueueSongs(shuffled, 0);
    }
  };

  const handleOpenAlbum = (album) => {
    navigate({ type: 'album', params: { ...album, channelTitle: artist.name } });
  };

  if (!artist) return null;

  const thumbnail = artist.thumbnail || songs[0]?.thumbnail || '';

  return (
    <div className="p-6 animate-fadeIn">
      <button
        onClick={navigateBack}
        className="flex items-center gap-2 text-on-surface-variant hover:text-on-surface mb-6 transition-colors"
      >
        <ArrowLeft size={20} />
        Back
      </button>

      <div className="flex items-center gap-6 mb-8 animate-slideDown">
        <div className="w-32 h-32 rounded-full overflow-hidden bg-gradient-to-br from-purple-600 to-purple-800 flex-shrink-0">
          {thumbnail ? (
            <ArtistAvatar name={artist.name} fallbackThumb={thumbnail} className="w-full h-full object-cover" />
          ) : (
            <div className="w-full h-full flex items-center justify-center">
              <Music size={48} className="text-on-surface/60" />
            </div>
          )}
        </div>
        <div className="flex-1 min-w-0">
          <h1 className="text-3xl font-bold text-on-surface mb-2">{artist.name}</h1>
          <p className="text-on-surface-variant">{songs.length} songs</p>
          <div className="flex gap-3 mt-4">
            <button
              onClick={handlePlayAll}
              className="flex items-center gap-2 px-6 py-2 bg-primary text-on-surface rounded-full hover:bg-primary/80 transition-colors"
            >
              <Play size={18} />
              Play All
            </button>
            <button
              onClick={handleShuffle}
              className="flex items-center gap-2 px-6 py-2 bg-surface-container-high text-on-surface rounded-full hover:bg-surface-container-highest transition-colors"
            >
              <Shuffle size={18} />
              Shuffle
            </button>

          </div>
        </div>
      </div>

      {albums.length > 0 && (
        <div className="mb-8 animate-slideUp">
          <h2 className="text-xl font-bold text-on-surface mb-4">Albums</h2>
          <div className="flex gap-4 overflow-x-auto pb-4">
            {albums.map((album, i) => (
              <div
                key={album.playlistId}
                onClick={() => handleOpenAlbum(album)}
                className="flex-shrink-0 w-40 cursor-pointer hover:scale-105 transition-transform animate-scaleIn"
                style={{ animationDelay: `${i * 0.08}s`, animationFillMode: 'backwards' }}
              >
                <ArtImage
                  src={album.thumbnail}
                  alt={album.title}
                  className="w-40 h-40 rounded-lg object-cover mb-2"
                />
                <p className="text-on-surface text-sm font-medium truncate">{album.title}</p>
                <p className="text-on-surface-variant text-xs">{album.videoCount} videos</p>
              </div>
            ))}
          </div>
        </div>
      )}

      <h2 className="text-xl font-bold text-on-surface mb-4">Songs</h2>

      {error && (
        <div className="bg-error-container/30 border border-error rounded-lg p-4 mb-6 text-on-error-container text-sm">
          {error}
        </div>
      )}

      {loading ? (
        <div className="text-center text-on-surface-variant py-8">
          <LoadingIndicator size="lg" className="mx-auto" />
          <p className="mt-4">Loading songs...</p>
        </div>
      ) : songs.length === 0 && !error ? (
        <p className="text-on-surface-variant text-center py-8">No songs found</p>
      ) : (
        <div className="space-y-2">
          {songs.map((song, i) => (
            <div
              key={song.videoId}
              className="flex items-center gap-4 p-3 bg-surface-container/50 rounded-xl hover:bg-surface-container transition-colors group cursor-pointer animate-slideUp"
              style={{ animationDelay: `${i * 0.04}s`, animationFillMode: 'backwards' }}
              onClick={() => handlePlaySong(song)}
            >
              <ArtImage src={song.thumbnail} alt="" className="w-12 h-12 rounded object-cover" />
              <div className="flex-1 min-w-0">
                <p className="text-on-surface font-medium truncate">{song.title}</p>
                <p className="text-on-surface-variant text-sm truncate">
                  {song.channelTitle}
                  {song.album && <span className="text-outline"> · {song.album}</span>}
                </p>
              </div>
              <span className="text-outline text-sm">
                {youtubeScraperService.formatDuration(song.duration)}
              </span>
              <div className="opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                <button
                  onClick={(e) => { e.stopPropagation(); handlePlaySong(song); }}
                  className="p-2 bg-primary text-on-surface rounded-full hover:bg-primary/80 transition-colors"
                >
                  <Play size={14} />
                </button>
                <button
                  onClick={(e) => { e.stopPropagation(); setPickerSong(song); }}
                  className="p-2 bg-surface-container-high text-on-surface rounded-full hover:bg-surface-container-highest transition-colors"
                  title="Add to playlist"
                >
                  <Plus size={14} />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {pickerSong && (
        <PlaylistPickerModal song={pickerSong} onClose={() => setPickerSong(null)} />
      )}
    </div>
  );
};
