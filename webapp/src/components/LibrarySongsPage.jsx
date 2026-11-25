import { ArrowLeft, Play, ListMusic } from 'lucide-react';
import { usePlayer } from '../context/PlayerContext';
import { useNavigate } from '../context/NavigationContext';
import { ArtImage } from './ArtImage';

function artistName(song) {
  return song.channelTitle || song.artists?.[0]?.name || '';
}

function formatDuration(seconds) {
  const s = Math.floor(seconds);
  const m = Math.floor(s / 60);
  return `${m}:${String(s % 60).padStart(2, '0')}`;
}

export const LibrarySongsPage = () => {
  const { subPage, navigateBack } = useNavigate();
  const { playSong } = usePlayer();
  const tracks = subPage?.params?.tracks || [];
  const title = subPage?.params?.title || '';

  const handlePlay = (song) => {
    playSong(song, tracks);
  };

  return (
    <div className="p-6 animate-fadeIn">
      <button
        onClick={navigateBack}
        className="flex items-center gap-2 text-on-surface-variant hover:text-on-surface mb-6 transition-colors"
      >
        <ArrowLeft size={20} />
        Back
      </button>

      <h1 className="text-2xl font-bold text-on-surface mb-1 flex items-center gap-2">
        <ListMusic size={24} className="text-primary" />
        {title}
      </h1>
      <p className="text-on-surface-variant mb-6">
        {tracks.length} song{tracks.length === 1 ? '' : 's'}
      </p>

      {tracks.length === 0 ? (
        <p className="text-on-surface-variant">No songs here.</p>
      ) : (
        <div className="bg-surface-container/30 rounded-2xl divide-y divide-outline-variant/20 overflow-hidden">
          {tracks.map((song, index) => (
            <button
              key={song.videoId}
              onClick={() => handlePlay(song)}
              className="w-full flex items-center gap-3 p-2.5 hover:bg-surface-container-high/50 transition-all text-left group"
              style={{ animationDelay: `${index * 0.02}s`, animationFillMode: 'backwards' }}
              title={song.title}
            >
              <ArtImage
                src={song.thumbnail}
                alt={song.title}
                className="w-12 h-12 rounded-xl object-cover shadow-md shrink-0"
              />
              <div className="flex-1 min-w-0">
                <p className="text-on-surface font-medium truncate">{song.title || 'Unknown Song'}</p>
                <p className="text-xs text-on-surface-variant truncate">
                  {artistName(song)}{song.duration > 0 ? `   ${formatDuration(song.duration)}` : ''}
                </p>
              </div>
              <span className="p-2.5 rounded-full bg-primary text-on-primary opacity-0 group-hover:opacity-100 transition-opacity">
                <Play size={16} fill="currentColor" />
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
};