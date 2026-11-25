import { useState, useRef, useEffect } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { useNavigate } from '../context/NavigationContext';
import { Play, Pause, SkipForward, SkipBack, ChevronUp, Shuffle, Repeat, Repeat1, Download, Volume2, VolumeX, ListMusic, MicVocal, ListPlus } from 'lucide-react';
import { LoadingIndicator } from './LoadingIndicator';
import { WavyProgressBar } from './WavyProgressBar';
import { QueuePanel } from './QueuePanel';
import { PlaylistPickerModal } from './PlaylistPickerModal';
import { Ripple } from './Ripple';
import { ArtImage } from './ArtImage';
import { useAlbumArt } from '../hooks/useAlbumArt';

export const Player = ({ playerExpanded }) => {
  const {
    currentSong,
    isPlaying,
    isLoading,
    volume,
    progress,
    duration,
    repeat,
    shuffle,
    togglePlay,
    playNext,
    playPrevious,
    seekTo,
    changeVolume,
    toggleRepeat,
    toggleShuffle,
    setPlayerExpanded,
    dragOffset,
    setDragOffset,
    setIsDragging,
    minimizeOffset,
    showQueue,
    setShowQueue,
    showLyrics,
    setShowLyrics,
    hasLyrics,
  } = usePlayer();
  const { navigate } = useNavigate();

  const [downloading, setDownloading] = useState(false);
  const [pickerSong, setPickerSong] = useState(null);
  const dragRef = useRef({ moved: false });
  const albumArt = useAlbumArt(currentSong);

  const handleDownload = async () => {
    if (!currentSong?.videoId || downloading) return;
    setDownloading(true);
    try {
      const params = new URLSearchParams();
      if (currentSong.title) params.set('title', currentSong.title);
      if (currentSong.channelTitle) params.set('artist', currentSong.channelTitle);
      if (currentSong.album) params.set('album', currentSong.album);
      const qs = params.toString();
      const res = await fetch(`/api/download/${currentSong.videoId}${qs ? '?' + qs : ''}`);
      if (!res.ok) throw new Error('Server error');
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${currentSong.title}.mp3`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 10000);
    } catch (err) {
      console.error('Download failed:', err);
    } finally {
      setDownloading(false);
    }
  };

  const handleSeek = (fraction) => {
    seekTo(Math.min(fraction * duration, Math.max(0, duration - 0.5)));
  };

  const formatTime = (s) => {
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };

  useEffect(() => {
    if (playerExpanded && dragOffset > 0) setDragOffset(0);
  }, [playerExpanded]);

  const handlePointerDown = (e) => {
    if (playerExpanded) return;
    const startY = e.clientY;
    let offset = 0;
    dragRef.current.moved = false;
    let lastY = e.clientY;
    let lastTime = Date.now();
    let velocity = 0;
    setIsDragging(true);

    const onMove = (ev) => {
      const now = Date.now();
      const dt = now - lastTime;
      if (dt > 0) {
        velocity = (lastY - ev.clientY) / dt;
        lastY = ev.clientY;
        lastTime = now;
      }
      const delta = startY - ev.clientY;
      if (delta > 5) dragRef.current.moved = true;
      offset = Math.max(0, delta);
      setDragOffset(offset);
    };

    const onUp = () => {
      document.removeEventListener('pointermove', onMove);
      document.removeEventListener('pointerup', onUp);
      setIsDragging(false);
      if (dragRef.current.moved && (offset > 60 || velocity > 0.3)) {
        setDragOffset(0);
        setPlayerExpanded(true);
      } else {
        setDragOffset(0);
      }
    };

    document.addEventListener('pointermove', onMove);
    document.addEventListener('pointerup', onUp);
  };

  if (!currentSong && !isLoading) return null;

  if (!currentSong && isLoading) {
    return (
      <div className="fixed bottom-0 left-0 right-0 z-30 flex justify-center">
        <div className="bg-surface-container/95 backdrop-blur-xl rounded-full shadow-2xl mx-4 mb-4 px-5 py-3 w-full max-w-5xl">
          <div className="flex items-center gap-3 justify-center">
            <LoadingIndicator size="sm" />
            <span className="text-sm text-on-surface-variant">Loading...</span>
          </div>
        </div>
      </div>
    );
  }

  const transform = dragOffset > 0
    ? `translateY(${-dragOffset}px)`
    : playerExpanded
      ? 'translateY(-100vh)'
      : 'translateY(0%)';

  return (
    <>
      <div
        className="fixed bottom-0 left-0 right-0 z-30 flex justify-center"
        style={{
          transform,
          opacity: dragOffset > 0
            ? Math.max(0, 1 - dragOffset / (window.innerHeight * 0.75))
            : minimizeOffset > 0
              ? Math.min(1, minimizeOffset / (window.innerHeight * 0.75))
              : (playerExpanded ? 0 : 1),
          transition: (dragOffset > 0 || minimizeOffset > 0) ? 'none' : 'transform 0.35s cubic-bezier(0.05, 0.7, 0.1, 1), opacity 0.35s cubic-bezier(0.05, 0.7, 0.1, 1)',
        }}
      >
        <div
          className="relative bg-surface-container/95 backdrop-blur-xl rounded-full shadow-2xl mx-4 mb-4 px-5 py-2 w-full max-w-5xl pointer-events-auto touch-none select-none"
          onClick={() => { if (!dragRef.current.moved) setPlayerExpanded(true); }}
          onPointerDown={handlePointerDown}
        >
          {isLoading && (
            <div className="absolute inset-0 bg-surface/60 rounded-full flex items-center justify-center z-10">
              <LoadingIndicator size="md" />
            </div>
          )}
          <div className="flex items-center gap-2">
            <div className="w-9 h-9 shrink-0">
              <ArtImage
                src={currentSong.thumbnail}
                alt={currentSong.title}
                className="w-9 h-9 rounded-lg object-cover shrink-0"
                fallbackSrc={albumArt}
              />
            </div>

            <div className="flex-1 min-w-0">
              <h3 className="font-medium truncate text-sm leading-tight">{currentSong.title}</h3>
              <p
                className="text-[11px] text-on-surface-variant truncate leading-tight cursor-pointer hover:text-on-surface"
                onClick={e => { e.stopPropagation(); navigate({ type: 'artist', params: { name: currentSong.channelTitle, artistId: currentSong.channelId || '', thumbnail: currentSong.thumbnail || '' } }); }}
              >{currentSong.channelTitle}</p>
            </div>

            <div className="flex items-center gap-0.5" onClick={e => e.stopPropagation()}>
              <button onClick={toggleShuffle} className={`p-1.5 rounded-full transition-colors ${shuffle ? 'text-primary' : 'text-on-surface-variant hover:text-on-surface'}`} title="Shuffle">
                <Shuffle size={15} />
              </button>
              <button onClick={playPrevious} className="p-1.5 hover:bg-surface-container-high rounded-full transition-colors">
                <SkipBack size={16} />
              </button>
              <Ripple className="rounded-full">
                <button onClick={togglePlay} className="p-2 bg-primary text-on-primary rounded-full shadow-md hover:scale-105 active:scale-95 transition-all">
                  {isPlaying ? <Pause size={18} /> : <Play size={18} />}
                </button>
              </Ripple>
              <button onClick={playNext} className="p-1.5 hover:bg-surface-container-high rounded-full transition-colors">
                <SkipForward size={16} />
              </button>
              <button onClick={toggleRepeat} className={`p-1.5 rounded-full transition-colors ${repeat !== 'off' ? 'text-primary' : 'text-on-surface-variant hover:text-on-surface'}`} title="Repeat">
                {repeat === 'one' ? <Repeat1 size={15} /> : <Repeat size={15} />}
              </button>
              <button
                onClick={handleDownload}
                disabled={downloading}
                className="p-1.5 text-on-surface-variant hover:text-on-surface rounded-full transition-colors disabled:opacity-50"
                title={downloading ? 'Downloading...' : 'Download MP3'}
              >
                <Download size={15} />
              </button>
              <button
                onClick={() => setPickerSong(currentSong)}
                className="p-1.5 text-on-surface-variant hover:text-on-surface rounded-full transition-colors"
                title="Add to playlist"
              >
                <ListPlus size={15} />
              </button>
              <button
                onClick={() => setShowQueue(true)}
                className={`p-1.5 rounded-full transition-colors ${showQueue ? 'text-primary' : 'text-on-surface-variant hover:text-on-surface'}`}
                title="Queue"
              >
                <ListMusic size={15} />
              </button>
              {hasLyrics && (
                <button
                  onClick={() => { setShowLyrics(true); setPlayerExpanded(true); }}
                  className={`p-1.5 rounded-full transition-colors ${showLyrics ? 'text-primary' : 'text-on-surface-variant hover:text-on-surface'}`}
                  title="Show lyrics"
                >
                  <MicVocal size={15} />
                </button>
              )}
              <div className="relative group ml-2" onPointerDown={e => e.stopPropagation()}>
                <button onClick={() => changeVolume(volume === 0 ? 1 : 0)} className="p-1.5 text-on-surface-variant hover:text-on-surface rounded-full transition-colors" title="Volume">
                  {volume === 0 ? <VolumeX size={15} /> : <Volume2 size={15} />}
                </button>
                <div className="absolute bottom-full left-1/2 -translate-x-1/2 flex-col items-center bg-surface-container-high rounded-xl px-3 pt-2 pb-2.5 shadow-lg gap-1 opacity-0 scale-75 origin-bottom transition-all duration-100 pointer-events-none group-hover:opacity-100 group-hover:scale-100 group-hover:pointer-events-auto">
                  <input
                    type="range"
                    min="0"
                    max="1"
                    step="0.01"
                    value={volume}
                    onChange={(e) => changeVolume(parseFloat(e.target.value))}
                    className="h-20 w-1 cursor-pointer accent-white [writing-mode:vertical-lr] [direction:rtl]"
                  />
                  {volume === 0 ? <VolumeX size={12} /> : <Volume2 size={12} />}
                </div>
              </div>
              <button onClick={() => setPlayerExpanded(true)} className="p-1.5 hover:bg-surface-container-high rounded-full transition-colors">
                <ChevronUp size={16} />
              </button>
            </div>
          </div>

          <div className="mt-1" onClick={e => e.stopPropagation()}>
            <WavyProgressBar
              progress={duration > 0 ? progress / duration : 0}
              height={4}
              onSeek={handleSeek}
            />
            <div className="flex justify-between text-[10px] text-on-surface-variant mt-0.5">
              <span>{formatTime(progress)}</span>
              <span>{formatTime(duration)}</span>
            </div>
          </div>
          </div>
      </div>

      {downloading && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-scrim/60 backdrop-blur-sm">
          <div className="bg-surface-container rounded-2xl p-8 flex flex-col items-center gap-4 shadow-2xl animate-scaleIn">
            <LoadingIndicator size="md" />
            <p className="text-on-surface text-lg font-medium">Please wait...</p>
            <p className="text-on-surface-variant text-sm truncate max-w-64">{currentSong?.title}</p>
          </div>
        </div>
      )}

      {showQueue && <QueuePanel onClose={() => setShowQueue(false)} />}
      {pickerSong && <PlaylistPickerModal song={pickerSong} onClose={() => setPickerSong(null)} />}
    </>
  );
};
