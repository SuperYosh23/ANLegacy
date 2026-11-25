import { useEffect, useState, useRef, useMemo, useCallback } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { useNavigate } from '../context/NavigationContext';
import { Play, Pause, SkipForward, SkipBack, Shuffle, Repeat, Repeat1, ChevronDown, Volume2, VolumeX, Download, ListMusic, MicVocal, ListPlus } from 'lucide-react';
import { LoadingIndicator } from './LoadingIndicator';
import { WavyProgressBar } from './WavyProgressBar';
import { QueuePanel } from './QueuePanel';
import { PlaylistPickerModal } from './PlaylistPickerModal';
import { RetryImage } from './RetryImage';
import { Ripple } from './Ripple';
import { apiService } from '../services/apiService';
import { useTrackArtwork } from '../hooks/useTrackArtwork';
import { useElementSize } from '../hooks/useElementSize';
import { storage } from '../utils/storage';

// The overlay is sized by the window minus the resizable sidebar, so its shape
// ranges from very tall and narrow (min window, wide sidebar) to very wide
// (maximized). Three layouts cover that range; every one of them derives its
// artwork size from the space actually left over after the text/scrubber/
// transport block, so nothing gets pushed out of view.
const SIDE_MIN_WIDTH = 780;
const SIDE_MIN_RATIO = 1.2;
const PORTRAIT_MAX_RATIO = 0.85;

const SCALES = {
  side: {
    artMax: 520,
    title: 'text-3xl', artist: 'text-lg', album: 'text-base',
    btn: 'p-2.5', btnIcon: 20, icon: 24, play: 'p-4', playIcon: 28,
    gap: 'gap-2', align: 'justify-start',
  },
  square: {
    artMax: 420,
    title: 'text-2xl', artist: 'text-base', album: 'text-sm',
    btn: 'p-2.5', btnIcon: 20, icon: 24, play: 'p-4', playIcon: 28,
    gap: 'gap-2.5', align: 'justify-center',
  },
  portrait: {
    artMax: 320,
    title: 'text-xl', artist: 'text-sm', album: 'text-xs',
    btn: 'p-2', btnIcon: 18, icon: 20, play: 'p-3', playIcon: 24,
    gap: 'gap-2', align: 'justify-center',
  },
};

// The lyrics side panel is much narrower than the main content column, so it
// gets its own button scale rather than the full-size one.
const COMPACT_SCALE = {
  btn: 'p-2', btnIcon: 16, icon: 20, play: 'p-3', playIcon: 24,
  gap: 'gap-1.5', align: 'justify-center',
};

const clamp = (value, min, max) => Math.max(min, Math.min(value, max));

const formatClock = (s) => {
  const m = Math.floor(s / 60);
  const sec = Math.floor(s % 60);
  return `${m}:${sec.toString().padStart(2, '0')}`;
};

function resolveLayout(width, height) {
  if (width <= 0 || height <= 0) return { mode: 'side', artSize: 288, scale: SCALES.side };

  if (width >= SIDE_MIN_WIDTH && width >= height * SIDE_MIN_RATIO) {
    return {
      mode: 'side',
      artSize: clamp(Math.min(width * 0.38, height - 170), 160, SCALES.side.artMax),
      scale: SCALES.side,
    };
  }

  const mode = width < height * PORTRAIT_MAX_RATIO ? 'portrait' : 'square';
  const scale = SCALES[mode];
  // Room for the minimize header, the padding around the content, the gap
  // above the text block, and the text block itself.
  const reserved = (mode === 'portrait' ? 300 : 328) + 64;
  return {
    mode,
    artSize: clamp(Math.min(width - 48, height - reserved), 120, scale.artMax),
    scale,
  };
}

function useActiveLyricLine(lyrics, progressMs) {
  return useMemo(() => {
    if (!lyrics?.lyrics || !Array.isArray(lyrics.lyrics)) return -1;
    const lines = lyrics.lyrics;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (progressMs >= line.start_time && progressMs < line.end_time) {
        return i;
      }
    }
    const lastIdx = lines.length - 1;
    if (lastIdx >= 0 && progressMs >= lines[lastIdx].end_time) return -2;
    return -1;
  }, [lyrics, progressMs]);
}

const ArtworkBlock = ({ size, src, prevSrc, alt, loading, onError, fallbackSrc, className = 'rounded-2xl shadow-2xl' }) => (
  <div
    className="relative flex-shrink-0"
    style={size === '100%' ? { width: '100%', aspectRatio: '1 / 1' } : { width: size, height: size }}
  >
    {prevSrc && (
      <img src={prevSrc} alt="" className={`absolute inset-0 w-full h-full object-cover ${className} animate-fadeOut`} />
    )}
    <RetryImage
      src={src}
      alt={alt}
      className={`w-full h-full object-cover ${className} ${prevSrc ? 'animate-fadeIn' : ''}`}
      onError={onError}
      fallbackSrc={fallbackSrc}
    />
    {loading && (
      <div className="absolute inset-0 bg-surface/60 rounded-2xl flex items-center justify-center z-10">
        <LoadingIndicator size={typeof size === 'number' && size >= 200 ? 'lg' : 'md'} />
      </div>
    )}
  </div>
);

const TrackMeta = ({ scale, center, title, artist, album, onArtist }) => (
  <div className={`space-y-1 ${center ? 'text-center' : ''}`}>
    <h2 className={`${scale.title} font-bold text-on-surface truncate`}>{title}</h2>
    <p
      className={`${scale.artist} text-on-surface truncate cursor-pointer hover:underline`}
      onClick={onArtist}
    >{artist}</p>
    {album && <p className={`${scale.album} text-outline truncate`}>{album}</p>}
  </div>
);

const Scrubber = ({ progress, duration, onSeek, barHeight = 6 }) => (
  <div className="space-y-3">
    <WavyProgressBar
      progress={duration > 0 ? progress / duration : 0}
      height={barHeight}
      onSeek={onSeek}
    />
    <div className="flex justify-between text-xs text-on-surface-variant">
      <span>{formatClock(progress)}</span>
      <span>{formatClock(duration)}</span>
    </div>
  </div>
);

const VolumeControl = ({ scale, volume, onToggle }) => (
  <div className="relative group">
    <button onClick={onToggle} className={`${scale.btn} text-on-surface-variant hover:text-on-surface rounded-full transition-colors`} title="Volume">
      {volume === 0 ? <VolumeX size={scale.btnIcon} /> : <Volume2 size={scale.btnIcon} />}
    </button>
    <div className="absolute bottom-full left-1/2 -translate-x-1/2 flex-col items-center bg-surface-container-high rounded-xl px-3 pt-2 pb-2.5 shadow-lg gap-1 opacity-0 scale-75 origin-bottom transition-all duration-100 pointer-events-none group-hover:opacity-100 group-hover:scale-100 group-hover:pointer-events-auto">
      <input
        type="range"
        min="0"
        max="1"
        step="0.01"
        value={volume}
        onChange={e => onToggle(Number(e.target.value), true)}
        className="h-20 w-1 cursor-pointer accent-white [writing-mode:vertical-lr] [direction:rtl]"
      />
      {volume === 0 ? <VolumeX size={12} /> : <Volume2 size={12} />}
    </div>
  </div>
);

// Two deliberate rows: the transport keys on top, the utility keys below.
// Both wrap as a safety net on very narrow windows.
const TransportControls = ({
  scale, shuffle, playing, repeat, downloading, showQueue, showLyrics, hasLyrics, volume,
  onShuffle, onTogglePlay, onPrevious, onNext, onRepeat, onDownload, onAdd, onQueue, onLyrics, onVolume,
}) => (
  <div className="flex flex-col gap-2">
    <div className={`flex flex-wrap items-center ${scale.gap} ${scale.align}`}>
      <button onClick={onShuffle} className={`${scale.btn} rounded-full transition-colors ${shuffle ? 'text-primary' : 'text-on-surface-variant hover:text-on-surface'}`} title="Shuffle">
        <Shuffle size={scale.icon} />
      </button>
      <button onClick={onPrevious} className={`${scale.btn} hover:bg-surface-container rounded-full transition-colors`} title="Previous">
        <SkipBack size={scale.icon} />
      </button>
      <Ripple className="rounded-full">
        <button onClick={onTogglePlay} className={`${scale.play} bg-primary text-on-primary rounded-full shadow-xl hover:scale-105 active:scale-95 transition-all`} title={playing ? 'Pause' : 'Play'}>
          {playing ? <Pause size={scale.playIcon} /> : <Play size={scale.playIcon} />}
        </button>
      </Ripple>
      <button onClick={onNext} className={`${scale.btn} hover:bg-surface-container rounded-full transition-colors`} title="Next">
        <SkipForward size={scale.icon} />
      </button>
      <button onClick={onRepeat} className={`${scale.btn} rounded-full transition-colors ${repeat !== 'off' ? 'text-primary' : 'text-on-surface-variant hover:text-on-surface'}`} title="Repeat">
        {repeat === 'one' ? <Repeat1 size={scale.icon} /> : <Repeat size={scale.icon} />}
      </button>
    </div>

    <div className={`flex flex-wrap items-center ${scale.gap} ${scale.align}`}>
      <button onClick={onDownload} disabled={downloading} className={`${scale.btn} text-on-surface-variant hover:text-on-surface rounded-full transition-colors disabled:opacity-50`} title="Download">
        <Download size={scale.btnIcon} />
      </button>
      <button onClick={onAdd} className={`${scale.btn} text-on-surface-variant hover:text-on-surface rounded-full transition-colors`} title="Add to playlist">
        <ListPlus size={scale.btnIcon} />
      </button>
      <button onClick={onQueue} className={`${scale.btn} rounded-full transition-colors ${showQueue ? 'text-primary' : 'text-on-surface-variant hover:text-on-surface'}`} title="Queue">
        <ListMusic size={scale.btnIcon} />
      </button>
      {hasLyrics && (
        <button onClick={onLyrics} className={`${scale.btn} rounded-full transition-colors ${showLyrics ? 'text-primary' : 'text-on-surface-variant hover:text-on-surface'}`} title={showLyrics ? 'Hide lyrics' : 'Show lyrics'}>
          <MicVocal size={scale.btnIcon} />
        </button>
      )}
      <VolumeControl scale={scale} volume={volume} onToggle={onVolume} />
    </div>
  </div>
);

export const ExpandedPlayer = ({ closing, onMinimize }) => {
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
    dragOffset,
    minimizeOffset,
    setMinimizeOffset,
    showQueue,
    setShowQueue,
    showLyrics,
    setShowLyrics,
    hasLyrics,
    setHasLyrics,
  } = usePlayer();
  const { navigate } = useNavigate();
  const { artwork: trackArtwork, blurred: trackBlur } = useTrackArtwork(currentSong);
  const [imgSrc, setImgSrc] = useState('');
  const [prevImgSrc, setPrevImgSrc] = useState(null);
  const [deezerFallback, setDeezerFallback] = useState(null);
  const [downloading, setDownloading] = useState(false);
  const [pickerSong, setPickerSong] = useState(null);
  const [entering, setEntering] = useState(true);
  const [lyrics, setLyrics] = useState(null);
  const [lyricsLoading, setLyricsLoading] = useState(false);
  const [lyricsError, setLyricsError] = useState(false);
  const dragRef = useRef({ moved: false });
  const rootRef = useRef(null);
  const lyricsContainerRef = useRef(null);
  const activeLineRef = useRef(null);
  const { width: boxWidth, height: boxHeight } = useElementSize(rootRef);
  const { mode, artSize, scale } = useMemo(
    () => resolveLayout(boxWidth, boxHeight),
    [boxWidth, boxHeight]
  );
  const stacked = mode !== 'side';
  const infoMaxWidth = stacked ? Math.min(artSize + 180, 520) : undefined;
  const progressMs = progress * 1000;
  const activeLine = useActiveLyricLine(lyrics, progressMs);
  const goToArtist = useCallback(() => navigate({
    type: 'artist',
    params: {
      name: currentSong?.channelTitle,
      artistId: currentSong?.channelId || '',
      thumbnail: currentSong?.thumbnail || '',
    },
  }), [navigate, currentSong]);

  useEffect(() => {
    if (dragOffset > 0 || minimizeOffset > 0) {
      setEntering(false);
    }
  }, [dragOffset, minimizeOffset]);

  useEffect(() => {
    if (!dragOffset && !minimizeOffset && !closing) {
      requestAnimationFrame(() => setEntering(false));
    }
  }, []);

  useEffect(() => {
    return () => { document.body.style.overflow = '' };
  }, []);

  useEffect(() => {
    if (trackArtwork && trackArtwork !== imgSrc) {
      setPrevImgSrc(imgSrc);
      setImgSrc(trackArtwork);
      setTimeout(() => setPrevImgSrc(null), 350);
    }
  }, [trackArtwork]);

  useEffect(() => {
    if (!currentSong) { setDeezerFallback(null); return; }
    const title = currentSong.album || currentSong.title;
    const artist = currentSong.channelTitle || '';
    apiService.getAlbumArt(title, artist).then(url => {
      if (url) setDeezerFallback(url);
    });
  }, [currentSong]);

  useEffect(() => {
    const videoId = currentSong?.videoId;
    if (!videoId) return;
    let cancelled = false;
    setLyrics(null);
    setLyricsLoading(false);
    setLyricsError(false);
    if (!showLyrics) return;
    setLyricsLoading(true);
    apiService.getLyrics(videoId).then(data => {
      if (cancelled) return;
      if (data?.error) {
        setLyricsError(true);
      } else {
        setLyrics(data);
      }
    }).catch(() => {
      if (!cancelled) setLyricsError(true);
    }).finally(() => {
      if (!cancelled) setLyricsLoading(false);
    });
    return () => { cancelled = true; };
  }, [currentSong?.videoId]);

  const checkLyricsAvailability = useCallback(async () => {
    if (!currentSong?.videoId) { setHasLyrics(null); return; }
    setHasLyrics(null);
    try {
      const avail = await apiService.checkLyrics(currentSong.videoId);
      setHasLyrics(avail);
    } catch {
      setHasLyrics(false);
    }
  }, [currentSong?.videoId]);

  useEffect(() => {
    checkLyricsAvailability();
  }, [checkLyricsAvailability]);

  useEffect(() => {
    if (showLyrics && activeLine >= 0 && activeLineRef.current) {
      activeLineRef.current.scrollIntoView({
        behavior: 'smooth',
        block: 'center',
      });
    }
  }, [activeLine, showLyrics]);

  const renderLyricsContent = () => {
    if (lyricsLoading) {
      return (
        <div className="flex items-center justify-center h-full">
          <LoadingIndicator size="md" />
        </div>
      );
    }
    if (lyricsError) {
      return (
        <div className="flex items-center justify-center h-full text-on-surface-variant text-center">
          <div>
            <MicVocal size={40} className="mx-auto mb-3 opacity-50" />
            <p>No lyrics available</p>
          </div>
        </div>
      );
    }
    if (hasTimedLyrics) {
      return (
        <div className="flex flex-col items-center justify-center min-h-full py-8">
          {lyrics.lyrics.map((line, i) => {
            const isPast = activeLine > i;
            const isActive = activeLine === i;
            const isFuture = activeLine >= 0 && activeLine < i;
            const isEnded = activeLine === -2;

            let opacity = '0.3';
            let scale = 'scale-100';
            let color = 'text-on-surface';
            if (isPast) {
              opacity = '0.25';
              color = 'text-on-surface-variant';
            }
            if (isActive) {
              opacity = '1';
              scale = 'scale-105';
              color = 'text-on-surface';
            }
            if (isFuture && !isEnded) {
              opacity = '0.5';
              color = 'text-on-surface-variant';
            }
            if (isEnded) {
              opacity = '0.25';
              color = 'text-on-surface-variant';
            }

            return (
              <div
                key={line.id ?? i}
                ref={isActive ? activeLineRef : null}
                className={`transition-all duration-300 ease-out py-2 text-center ${scale}`}
                style={{ opacity }}
              >
                <span className={`${isActive ? 'text-2xl font-bold' : 'text-lg'} leading-relaxed ${color}`}>
                  {line.text || <span className="select-none">&zwnj;</span>}
                </span>
              </div>
            );
          })}
        </div>
      );
    }
    if (lyrics?.lyrics) {
      return (
        <div className="flex flex-col items-center justify-center min-h-full py-8">
          <pre className="text-base text-on-surface-variant leading-relaxed whitespace-pre-wrap font-sans text-center">
            {lyrics.lyrics}
          </pre>
        </div>
      );
    }
    return (
      <div className="flex items-center justify-center h-full text-on-surface-variant text-center">
        <p>No lyrics available</p>
      </div>
    );
  };

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

  const handleToggleLyrics = async () => {
    if (showLyrics) {
      setShowLyrics(false);
      return;
    }
    if (lyrics) {
      setShowLyrics(true);
      return;
    }
    if (!currentSong?.videoId) return;
    setLyricsLoading(true);
    setLyricsError(false);
    try {
      const data = await apiService.getLyrics(currentSong.videoId);
      if (data?.error) {
        setLyricsError(true);
      } else {
        setLyrics(data);
        setShowLyrics(true);
      }
    } catch {
      setLyricsError(true);
    } finally {
      setLyricsLoading(false);
    }
  };

  const handleSeek = (fraction) => {
    seekTo(Math.min(fraction * duration, Math.max(0, duration - 0.5)));
  };

  const handleVolume = (next, fromSlider) => {
    if (fromSlider) changeVolume(next);
    else changeVolume(volume === 0 ? 1 : 0);
  };

  const handleHeaderPointerDown = (e) => {
    const startY = e.clientY;
    let offset = 0;
    dragRef.current.moved = false;
    let lastY = e.clientY;
    let lastTime = Date.now();
    let velocity = 0;

    const onMove = (ev) => {
      const now = Date.now();
      const dt = now - lastTime;
      if (dt > 0) {
        velocity = (ev.clientY - lastY) / dt;
        lastY = ev.clientY;
        lastTime = now;
      }
      const delta = ev.clientY - startY;
      if (delta > 5) dragRef.current.moved = true;
      offset = Math.max(0, delta);
      setMinimizeOffset(offset);
    };

    const onUp = () => {
      document.removeEventListener('pointermove', onMove);
      document.removeEventListener('pointerup', onUp);
      setMinimizeOffset(0);
      if ((dragRef.current.moved && offset > 80) || velocity > 0.3) {
        onMinimize();
      }
    };

    document.addEventListener('pointermove', onMove);
    document.addEventListener('pointerup', onUp);
  };

  const hasTimedLyrics = lyrics?.hasTimestamps && Array.isArray(lyrics.lyrics);

  const transport = {
    scale,
    shuffle,
    playing: isPlaying,
    repeat,
    downloading,
    showQueue,
    showLyrics,
    hasLyrics,
    volume,
    onShuffle: toggleShuffle,
    onTogglePlay: togglePlay,
    onPrevious: playPrevious,
    onNext: playNext,
    onRepeat: toggleRepeat,
    onDownload: handleDownload,
    onAdd: () => setPickerSong(currentSong),
    onQueue: () => setShowQueue(true),
    onLyrics: handleToggleLyrics,
    onVolume: handleVolume,
  };

  if (!currentSong && !isLoading) return null;

  const expanding = dragOffset > 0;
  const minimizing = minimizeOffset > 0;
  const anyDrag = expanding || minimizing;

  const expandTransform = minimizing
    ? `translateY(${minimizeOffset}px)`
    : expanding
      ? `translateY(calc(100% - ${dragOffset}px))`
      : (entering || closing)
        ? 'translateY(100%)'
        : 'translateY(0%)';

  return (
    <div
      ref={rootRef}
      className="h-full flex flex-col bg-surface-dim text-on-surface relative overflow-hidden z-0"
      style={{
        transform: expandTransform,
        transition: anyDrag ? 'none' : 'transform 0.35s cubic-bezier(0.05, 0.7, 0.1, 1)',
      }}
    >
      {/* Port of mobile LTPlayerViewController.setArtworkImage background */}
      {storage.getPreferences().artworkBackground && trackBlur && (
        <div
          aria-hidden
          className="absolute inset-0 -z-10 bg-center bg-cover pointer-events-none"
          style={{ backgroundImage: `url(${trackBlur})` }}
        >
          <div className="absolute inset-0 bg-scrim/55" />
        </div>
      )}

      {/* Header */}
      <div
        className="flex items-center justify-end px-6 py-4 touch-none select-none"
        onPointerDown={handleHeaderPointerDown}
      >
        <button
          onClick={onMinimize}
          className="p-2 hover:bg-surface-container rounded-full transition-colors"
          title="Minimize"
        >
          <ChevronDown size={20} />
        </button>
      </div>

      {/* Main content, centred in the space under the header. `safe center`
          degrades to top alignment when the content is taller than a short
          window, so the overflow stays scrollable instead of being clipped. */}
      <div className={`flex-1 min-h-0 flex flex-col px-6 pb-8 ${stacked ? 'overflow-y-auto [justify-content:safe_center]' : 'justify-center'}`}>
        {!currentSong && isLoading ? (
          <div className="flex flex-col items-center justify-center gap-4 h-full animate-fadeIn">
            <LoadingIndicator size="lg" />
            <p className="text-on-surface-variant text-lg">Loading...</p>
          </div>
        ) : showLyrics ? (
          stacked ? (
            <div key="lyrics-stacked" className="flex flex-col gap-6 w-full animate-fadeInUp">
              <div className="flex flex-col items-center gap-4 shrink-0" style={{ maxWidth: infoMaxWidth }}>
                <ArtworkBlock
                  size={artSize}
                  src={imgSrc}
                  prevSrc={prevImgSrc}
                  alt={currentSong.title}
                  loading={isLoading}
                  fallbackSrc={deezerFallback}
                />
                <TrackMeta
                  scale={scale}
                  center
                  title={currentSong.title}
                  artist={currentSong.channelTitle}
                  album={currentSong.album}
                  onArtist={goToArtist}
                />
                <Scrubber progress={progress} duration={duration} onSeek={handleSeek} barHeight={4} />
                <TransportControls {...transport} />
              </div>

              <div
                ref={lyricsContainerRef}
                className="min-h-[8rem] overflow-y-auto scroll-smooth px-4"
                style={{ scrollbarWidth: 'none', msOverflowStyle: 'none' }}
              >
                {renderLyricsContent()}
              </div>
            </div>
          ) : (
            <div key="lyrics-side" className="flex gap-12 w-full max-w-5xl h-full items-stretch animate-fadeInUp">
              {/* Synced lyrics panel */}
              <div className="flex-1 flex flex-col justify-center min-w-0 min-h-0">
                <div
                  ref={lyricsContainerRef}
                  className="h-full max-h-full overflow-y-auto scroll-smooth px-4"
                  style={{ scrollbarWidth: 'none', msOverflowStyle: 'none' }}
                >
                  {renderLyricsContent()}
                </div>
              </div>

              {/* Compact side panel */}
              <div
                className="flex flex-col justify-center gap-6 shrink-0"
                style={{ width: clamp(Math.round(artSize * 0.72), 200, 300) }}
              >
                <ArtworkBlock
                  size="100%"
                  src={imgSrc}
                  alt={currentSong.title}
                  loading={isLoading}
                  fallbackSrc={deezerFallback}
                  className="rounded-2xl object-cover shadow-lg"
                />
                <div className="space-y-1 text-center">
                  <h3 className="text-base font-semibold text-on-surface truncate">{currentSong.title}</h3>
                  <p
                    className="text-sm text-on-surface-variant truncate cursor-pointer hover:text-on-surface"
                    onClick={goToArtist}
                  >{currentSong.channelTitle}</p>
                </div>
                <Scrubber progress={progress} duration={duration} onSeek={handleSeek} barHeight={4} />
                <TransportControls {...transport} scale={COMPACT_SCALE} />
              </div>
            </div>
          )
        ) : stacked ? (
          <div key="normal-stacked" className="flex flex-col items-center gap-5 w-full animate-fadeInUp">
            <ArtworkBlock
              size={artSize}
              src={imgSrc}
              prevSrc={prevImgSrc}
              alt={currentSong.title}
              loading={isLoading}
              onError={() => currentSong?.thumbnail && setImgSrc(currentSong.thumbnail)}
              fallbackSrc={deezerFallback}
            />
            <div className="w-full flex flex-col gap-4" style={{ maxWidth: infoMaxWidth }}>
              <TrackMeta
                scale={scale}
                center
                title={currentSong.title}
                artist={currentSong.channelTitle}
                album={currentSong.album}
                onArtist={goToArtist}
              />
              <Scrubber progress={progress} duration={duration} onSeek={handleSeek} />
              <TransportControls {...transport} />
            </div>
          </div>
        ) : (
          <div key="normal-side" className="flex gap-12 w-full max-w-4xl animate-fadeInUp">
            <div className="flex items-center shrink-0">
              <ArtworkBlock
                size={artSize}
                src={imgSrc}
                prevSrc={prevImgSrc}
                alt={currentSong.title}
                loading={isLoading}
                onError={() => currentSong?.thumbnail && setImgSrc(currentSong.thumbnail)}
                fallbackSrc={deezerFallback}
              />
            </div>

            <div className="flex-1 min-w-0 flex flex-col justify-between gap-8">
              <TrackMeta
                scale={scale}
                title={currentSong.title}
                artist={currentSong.channelTitle}
                album={currentSong.album}
                onArtist={goToArtist}
              />
              <div className="space-y-4">
                <Scrubber progress={progress} duration={duration} onSeek={handleSeek} />
                <TransportControls {...transport} />
              </div>
            </div>
          </div>
        )}
      </div>


      {downloading && (
        <div className="absolute inset-0 z-20 flex items-center justify-center bg-scrim/60 backdrop-blur-sm">
          <div className="bg-surface-container rounded-2xl p-8 flex flex-col items-center gap-4 shadow-2xl animate-scaleIn">
            <LoadingIndicator size="md" />
            <p className="text-on-surface text-lg font-medium">Please wait...</p>
            <p className="text-on-surface-variant text-sm truncate max-w-64">{currentSong?.title}</p>
          </div>
        </div>
      )}

      {showQueue && <QueuePanel onClose={() => setShowQueue(false)} />}
      {pickerSong && <PlaylistPickerModal song={pickerSong} onClose={() => setPickerSong(null)} />}
    </div>
  );
};
