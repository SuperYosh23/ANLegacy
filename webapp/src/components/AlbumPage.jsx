import { useState, useEffect } from 'react';
import { ArrowLeft, Play, Shuffle } from 'lucide-react';
import { usePlayer } from '../context/PlayerContext';
import { useNavigate } from '../context/NavigationContext';
import { youtubeScraperService } from '../services/youtubeScraper';
import { LoadingIndicator } from './LoadingIndicator';
import { ArtImage } from './ArtImage';
import { apiService } from '../services/apiService';

export const AlbumPage = () => {
  const { subPage, navigateBack } = useNavigate();
  const { playSong, setQueueSongs, currentSong } = usePlayer();
  const [tracks, setTracks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [deezerFallback, setDeezerFallback] = useState(null);

  const album = subPage?.params;

  useEffect(() => {
    if (!album?.playlistId) return;
    setLoading(true);
    setError('');
    youtubeScraperService.getPlaylistTracks(album.playlistId)
      .then(data => {
        setTracks(data);
      })
      .catch(err => { console.error('Failed to load album tracks:', err); setError('Could not reach the music backend.'); })
      .finally(() => setLoading(false));
  }, [album?.playlistId]);

  useEffect(() => {
    if (!album) { setDeezerFallback(null); return; }
    apiService.getAlbumArt(album.title, album.channelTitle || '').then(url => {
      if (url) setDeezerFallback(url);
    });
  }, [album]);

  if (!album) return null;

  const handlePlayAll = () => {
    if (tracks.length > 0) setQueueSongs(tracks, 0);
  };

  const handleShuffle = () => {
    if (tracks.length > 0) {
      const s = [...tracks].sort(() => Math.random() - 0.5);
      setQueueSongs(s, 0);
    }
  };

  const handlePlayTrack = (track) => {
    playSong(track, tracks);
  };

  return (
    <div className="p-6 animate-fadeIn">
      <button
        onClick={navigateBack}
        className="flex items-center gap-2 text-on-surface-variant hover:text-on-surface mb-6 transition-colors"
      >
        <ArrowLeft size={20} /> Back
      </button>

      <div className="flex items-center gap-6 mb-8 animate-slideDown">
        <ArtImage
          src={album.thumbnail}
          alt={album.title}
          className="w-40 h-40 rounded-xl object-cover shadow-lg"
          fallbackSrc={deezerFallback}
        />
        <div className="flex-1 min-w-0">
          <h1 className="text-3xl font-bold text-on-surface mb-2">{album.title}</h1>
          <p className="text-on-surface-variant mb-1">{album.channelTitle}</p>
          <p className="text-outline text-sm mb-4">{tracks.length} tracks</p>
          <div className="flex gap-3">
            <button
              onClick={handlePlayAll}
              className="flex items-center gap-2 px-6 py-2 bg-primary text-on-surface rounded-full hover:bg-primary/80 transition-colors"
            >
              <Play size={18} /> Play All
            </button>
            <button
              onClick={handleShuffle}
              className="flex items-center gap-2 px-6 py-2 bg-surface-container-high text-on-surface rounded-full hover:bg-surface-container-highest transition-colors"
            >
              <Shuffle size={18} /> Shuffle
            </button>
          </div>
        </div>
      </div>

      {error && (
        <div className="bg-error-container/30 border border-error rounded-lg p-4 mb-6 text-on-error-container text-sm">
          {error}
        </div>
      )}

      {loading ? (
        <div className="text-center text-on-surface-variant py-8">
          <LoadingIndicator size="lg" className="mx-auto" />
          <p className="mt-4">Loading tracks...</p>
        </div>
      ) : tracks.length === 0 && !error ? (
        <p className="text-on-surface-variant text-center py-8">No tracks found</p>
      ) : (
        <div className="space-y-2">
          {tracks.map((track, i) => (
            <div
              key={track.videoId}
              className={`flex items-center gap-4 p-3 rounded-xl transition-colors group cursor-pointer animate-slideUp ${
                currentSong?.videoId === track.videoId ? 'bg-primary/20' : 'bg-surface-container/50 hover:bg-surface-container'
              }`}
              style={{ animationDelay: `${i * 0.04}s`, animationFillMode: 'backwards' }}
              onClick={() => handlePlayTrack(track)}
            >
              <ArtImage src={track.thumbnail} alt="" className="w-12 h-12 rounded object-cover" />
              <div className="flex-1 min-w-0">
                <p className="text-on-surface font-medium truncate">{track.title}</p>
                <p className="text-on-surface-variant text-sm truncate">
                  {track.channelTitle}
                  {track.album && <span className="text-outline"> · {track.album}</span>}
                </p>
              </div>
              <span className="text-outline text-sm">
                {youtubeScraperService.formatDuration(track.duration)}
              </span>
              <div className="opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  onClick={(e) => { e.stopPropagation(); handlePlayTrack(track); }}
                  className="p-2 bg-primary text-on-surface rounded-full hover:bg-primary/80"
                >
                  <Play size={14} />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
