import { useState, useRef, useEffect } from 'react';
import { X, GripVertical, Trash2, Music } from 'lucide-react';
import { usePlayer } from '../context/PlayerContext';
import { ArtImage } from './ArtImage';
import { useBlurredArtwork } from '../hooks/useTrackArtwork';
import { storage } from '../utils/storage';

export const QueuePanel = ({ onClose }) => {
  const { queue, currentIndex, currentSong, removeFromQueue, reorderQueue, shuffle } = usePlayer();
  const artworkBackground = storage.getPreferences().artworkBackground;
  const queueBlur = useBlurredArtwork(artworkBackground ? currentSong : null);

  const formatDuration = (s) => {
    if (!s) return '';
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };
  const [dragIndex, setDragIndex] = useState(null);
  const [dragOverIndex, setDragOverIndex] = useState(null);
  const [closing, setClosing] = useState(false);
  const panelRef = useRef(null);

  const handleClose = () => {
    if (closing) return;
    setClosing(true);
    setTimeout(() => onClose?.(), 100);
  };

  useEffect(() => {
    const handleKey = (e) => {
      if (e.key === 'Escape') handleClose();
    };
    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [onClose, closing]);

  useEffect(() => {
    const handleClickOutside = (e) => {
      if (panelRef.current && !panelRef.current.contains(e.target)) {
        handleClose();
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose, closing]);

  const upcoming = queue.slice(currentIndex + 1);
  const previous = queue.slice(0, currentIndex);

  return (
    <div className={`fixed inset-0 z-[60] flex items-end justify-center bg-scrim/50 backdrop-blur-sm ${closing ? 'animate-fadeOut [animation-duration:100ms]' : 'animate-fadeIn'}`}>
      {/* Port of mobile LTQueueViewController background: blurred now-playing art + scrim */}
      {queueBlur && (
        <div
          aria-hidden
          className="absolute inset-0 -z-10 bg-center bg-cover pointer-events-none"
          style={{ backgroundImage: `url(${queueBlur})` }}
        >
          <div className="absolute inset-0 bg-scrim/55" />
        </div>
      )}
      <div
        ref={panelRef}
        className={`bg-surface-container-low rounded-t-3xl shadow-2xl w-full max-w-2xl max-h-[80vh] flex flex-col ${closing ? 'animate-slideDownToBottom [animation-duration:100ms]' : 'animate-slideUpFromBottom'}`}
      >
        <div className="flex items-center justify-between px-6 py-4 border-b border-outline-variant shrink-0">
          <h2 className="text-lg font-bold text-on-surface flex items-center gap-2">
            <Music size={20} /> Queue
            <span className="text-sm font-normal text-on-surface-variant">({queue.length} songs)</span>
          </h2>
          <button
            onClick={handleClose}
            className="p-2 hover:bg-surface-container rounded-full transition-colors"
          >
            <X size={20} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-4 py-3 space-y-1">
          {queue.length === 0 ? (
            <p className="text-on-surface-variant text-center py-8">Queue is empty</p>
          ) : (
            <>
              {currentSong && (
                <div className="flex items-center gap-3 px-3 py-2.5 rounded-xl bg-primary/20">
                  <div className="w-1 h-8 bg-primary rounded-full shrink-0" />
                  <div className="relative shrink-0">
                    <ArtImage src={currentSong.thumbnail} alt="" className="w-10 h-10 rounded object-cover" />
                    {currentSong.duration > 0 && (
                      <span className="absolute bottom-0.5 right-0.5 bg-black/70 text-white text-[9px] px-1 rounded leading-tight">{formatDuration(currentSong.duration)}</span>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-on-surface truncate">{currentSong.title}</p>
                    <p className="text-xs text-on-surface-variant truncate">
                      {currentSong.channelTitle}
                      {currentSong.album && <span className="text-outline"> · {currentSong.album}</span>}
                    </p>
                  </div>
                  <span className="text-xs text-outline shrink-0">Now playing</span>
                </div>
              )}

              {previous.length > 0 && (
                <div className="pt-4 pb-1">
                  <p className="text-xs font-semibold text-outline uppercase tracking-wider px-3">Previous</p>
                </div>
              )}
              {previous.map((song, _i) => (
                <div
                  key={song.videoId}
                  className="flex items-center gap-3 px-3 py-2 rounded-xl bg-surface-container/30 opacity-50"
                >
                  <div className="relative shrink-0">
                    <ArtImage src={song.thumbnail} alt="" className="w-9 h-9 rounded object-cover" />
                    {song.duration > 0 && (
                      <span className="absolute bottom-0.5 right-0.5 bg-black/70 text-white text-[8px] px-0.5 rounded leading-tight">{formatDuration(song.duration)}</span>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-on-surface truncate">{song.title}</p>
                    <p className="text-xs text-on-surface-variant truncate">
                      {song.channelTitle}
                      {song.album && <span className="text-outline"> · {song.album}</span>}
                    </p>
                  </div>
                </div>
              ))}

              {upcoming.length > 0 && (
                <div className="pt-4 pb-1">
                  <p className="text-xs font-semibold text-outline uppercase tracking-wider px-3">Up next</p>
                </div>
              )}
              {upcoming.map((song, i) => {
                const queueIndex = currentIndex + 1 + i;
                return (
                  <div
                    key={song.videoId}
                    draggable={!shuffle}
                    onDragStart={() => { setDragIndex(queueIndex); setDragOverIndex(queueIndex); }}
                    onDragOver={(e) => { e.preventDefault(); setDragOverIndex(queueIndex); }}
                    onDrop={() => {
                      if (dragIndex !== null && dragIndex !== queueIndex) {
                        reorderQueue(dragIndex, queueIndex);
                      }
                      setDragIndex(null);
                      setDragOverIndex(null);
                    }}
                    onDragEnd={() => { setDragIndex(null); setDragOverIndex(null); }}
                    className={`flex items-center gap-3 px-3 py-2.5 rounded-xl transition-colors group ${
                      dragOverIndex === queueIndex ? 'ring-2 ring-primary bg-surface-container' : 'bg-surface-container/50 hover:bg-surface-container'
                    }`}
                  >
                    {!shuffle && (
                      <div className="cursor-grab active:cursor-grabbing text-outline opacity-0 group-hover:opacity-100 transition-opacity shrink-0">
                        <GripVertical size={16} />
                      </div>
                    )}
                    <ArtImage src={song.thumbnail} alt="" className="w-9 h-9 rounded object-cover shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm text-on-surface truncate">{song.title}</p>
                      <p className="text-xs text-on-surface-variant truncate">
                        {song.channelTitle}
                        {song.album && <span className="text-outline"> · {song.album}</span>}
                      </p>
                    </div>
                    <button
                      onClick={() => removeFromQueue(queueIndex)}
                      className="p-1.5 text-on-surface-variant hover:text-error hover:bg-error-container/30 rounded-full transition-colors opacity-0 group-hover:opacity-100 shrink-0"
                      title="Remove from queue"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                );
              })}
            </>
          )}
        </div>
      </div>
    </div>
  );
};
