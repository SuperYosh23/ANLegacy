import { createContext, useContext, useState, useRef, useEffect, useCallback } from 'react';
import { historyUtils, statsUtils, eqStorage, eqPresetStorage } from '../utils/storage';
import { apiService } from '../services/apiService';
import { EQ_BANDS_POOL, EQ_DEFAULT_BAND_INDICES, EQ_BAND_COUNT_MIN, findNextBandIndex, createEqEngine } from '../utils/eqEngine';

const PlayerContext = createContext();

export const usePlayer = () => {
  const context = useContext(PlayerContext);
  if (!context) {
    throw new Error('usePlayer must be used within a PlayerProvider');
  }
  return context;
};

function shuffleArray(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const DEFAULT_EQ_INDICES = [...EQ_DEFAULT_BAND_INDICES];
const DEFAULT_EQ_GAINS = DEFAULT_EQ_INDICES.map(() => 0);

export const PlayerProvider = ({ children }) => {
  const [currentSong, setCurrentSong] = useState(null);
  const [queue, setQueue] = useState([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [volume, setVolume] = useState(1);
  const [progress, setProgress] = useState(0);
  const [duration, setDuration] = useState(0);
  const [repeat, setRepeat] = useState('off');
  const [shuffle, setShuffle] = useState(false);
  const [playerExpanded, setPlayerExpanded] = useState(false);
  const [dragOffset, setDragOffset] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [minimizeOffset, setMinimizeOffset] = useState(0);
  const [showQueue, setShowQueue] = useState(false);
  const [showLyrics, setShowLyrics] = useState(false);
  const [hasLyrics, setHasLyrics] = useState(null);
  const [userPresets, setUserPresets] = useState(() => eqPresetStorage.getPresets());

  useEffect(() => {
    const handler = () => setUserPresets(eqPresetStorage.getPresets());
    window.addEventListener('eq-presets-changed', handler);
    return () => window.removeEventListener('eq-presets-changed', handler);
  }, []);

  const [eqEnabled, setEqEnabled] = useState(() => {
    const saved = eqStorage.getSettings();
    return saved ? true : false;
  });
  const [eqIndices, setEqIndices] = useState(() => {
    const saved = eqStorage.getSettings();
    return saved?.indices && saved.indices.length >= EQ_BAND_COUNT_MIN
      ? saved.indices
      : [...DEFAULT_EQ_INDICES];
  });
  const [eqGains, setEqGains] = useState(() => {
    const saved = eqStorage.getSettings();
    return saved?.gains && saved.gains.length >= EQ_BAND_COUNT_MIN
      ? saved.gains
      : [...DEFAULT_EQ_GAINS];
  });

  const audioRef = useRef(null);
  const intervalRef = useRef(null);
  const playNextRef = useRef(null);
  const volumeRef = useRef(volume);
  const originalQueueRef = useRef([]);
  const shuffledIndicesRef = useRef([]);
  const loadingRef = useRef(false);
  const eqEngineRef = useRef(null);
  const eqAnalyserRef = useRef(null);
  const eqIndicesRef = useRef(eqIndices);
  const currentSongRef = useRef(null);
  const statsBaseRef = useRef(0);
  currentSongRef.current = currentSong;

  volumeRef.current = volume;
  eqIndicesRef.current = eqIndices;

  const commitStatsDelta = useCallback(() => {
    const song = currentSongRef.current;
    const audio = audioRef.current;
    if (!song?.videoId || !audio || audio.paused) {
      statsBaseRef.current = audio ? audio.currentTime : 0;
      return;
    }
    const now = audio.currentTime;
    if (now <= statsBaseRef.current) {
      statsBaseRef.current = now;
      return;
    }
    const delta = now - statsBaseRef.current;
    statsBaseRef.current = now;
    if (delta > 0) statsUtils.addListenedSeconds(song, delta);
  }, []);
  const commitStatsDeltaRef = useRef(commitStatsDelta);
  commitStatsDeltaRef.current = commitStatsDelta;

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const onEnded = () => playNextRef.current?.();
    const onError = () => console.error('[Player] Audio error');
    const onLoadedMetadata = () => {
      if (audio.duration > 0 && isFinite(audio.duration)) {
        setDuration(audio.duration);
      }
    };

    audio.addEventListener('ended', onEnded);
    audio.addEventListener('error', onError);
    audio.addEventListener('loadedmetadata', onLoadedMetadata);

    return () => {
      audio.removeEventListener('ended', onEnded);
      audio.removeEventListener('error', onError);
      audio.removeEventListener('loadedmetadata', onLoadedMetadata);
    };
  }, []);

  useEffect(() => {
    if (isPlaying && audioRef.current) {
      intervalRef.current = setInterval(() => {
        if (audioRef.current && !audioRef.current.paused) {
          setProgress(audioRef.current.currentTime);
          const dur = audioRef.current.duration;
          if (dur > 0 && isFinite(dur)) setDuration(dur);
        }
      }, 10);
    } else {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    }

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, [isPlaying]);

  useEffect(() => {
    if (currentSong) {
      statsUtils.recordTrackPlay(currentSong);
      historyUtils.addToHistory(currentSong);
    }
    statsBaseRef.current = 0;
  }, [currentSong]);

  useEffect(() => {
    if (!isPlaying) return;
    const tick = setInterval(() => commitStatsDeltaRef.current(), 10000);
    return () => clearInterval(tick);
  }, [isPlaying]);

  useEffect(() => {
    const ids = [];
    for (let i = currentIndex; i < Math.min(currentIndex + 4, queue.length); i++) {
      const song = queue[i];
      if (song?.videoId) ids.push(song.videoId);
    }
    if (ids.length > 0) apiService.prefetchLyrics(ids);
  }, [queue, currentIndex]);

  useEffect(() => {
    return () => {
      if (eqEngineRef.current) {
        eqEngineRef.current.destroy();
        eqEngineRef.current = null;
      }
    };
  }, []);

  useEffect(() => {
    if (eqEngineRef.current) {
      eqEngineRef.current.setEnabled(eqEnabled, eqIndices, eqGains);
    }
  }, [eqEnabled, eqIndices, eqGains]);

  const setEqBand = useCallback((index, value) => {
    setEqGains(prev => {
      const next = [...prev];
      next[index] = value;
      const indices = eqIndicesRef.current;
      eqStorage.saveSettings({ indices, gains: next });
      if (eqEngineRef.current) {
        eqEngineRef.current.setGain(indices[index], value);
      }
      return next;
    });
  }, []);

  const addEqBand = useCallback(() => {
    setEqIndices(prev => {
      if (prev.length >= EQ_BANDS_POOL.length) return prev;
      const nextIdx = findNextBandIndex(prev);
      if (nextIdx === -1) return prev;
      const newIndices = [...prev, nextIdx].sort((a, b) => a - b);
      const insertPos = newIndices.indexOf(nextIdx);
      setEqGains(gainsPrev => {
        const newGains = [...gainsPrev];
        newGains.splice(insertPos, 0, 0);
        eqStorage.saveSettings({ indices: newIndices, gains: newGains });
        return newGains;
      });
      return newIndices;
    });
  }, []);

  const removeEqBand = useCallback(() => {
    setEqIndices(prev => {
      if (prev.length <= EQ_BAND_COUNT_MIN) return prev;
      const toRemove = prev[prev.length - 1];
      const removePos = prev.indexOf(toRemove);
      const newIndices = prev.filter(i => i !== toRemove);
      setEqGains(gainsPrev => {
        const newGains = [...gainsPrev];
        newGains.splice(removePos, 1);
        eqStorage.saveSettings({ indices: newIndices, gains: newGains });
        return newGains;
      });
      if (eqEngineRef.current) {
        eqEngineRef.current.setGain(toRemove, 0);
      }
      return newIndices;
    });
  }, []);

  const toggleEq = useCallback(() => {
    setEqEnabled(prev => !prev);
  }, []);

  const resetEq = useCallback(() => {
    setEqEnabled(false);
    const defaultIndices = [...DEFAULT_EQ_INDICES];
    const defaultGains = DEFAULT_EQ_INDICES.map(() => 0);
    setEqIndices(defaultIndices);
    setEqGains(defaultGains);
    eqStorage.clear();
    if (eqEngineRef.current) {
      eqEngineRef.current.setEnabled(false, defaultIndices, defaultGains);
    }
  }, []);

  const applyPreset = useCallback((gains, indices) => {
    const targetIndices = indices ?? eqIndices;
    setEqEnabled(true);
    setEqGains(gains);
    setEqIndices(targetIndices);
    eqStorage.saveSettings({ indices: targetIndices, gains });
    if (eqEngineRef.current) {
      eqEngineRef.current.setEnabled(true, targetIndices, gains);
    }
  }, [eqIndices]);

  const saveCurrentPreset = useCallback((name) => {
    eqPresetStorage.savePreset(name, eqIndices, eqGains);
  }, [eqIndices, eqGains]);

  const deleteUserPreset = useCallback((name) => {
    eqPresetStorage.deletePreset(name);
  }, []);

  const loadAndPlay = async (song) => {
    if (!audioRef.current || loadingRef.current) return;
    if (!song?.videoId) return;

    if (!eqEngineRef.current) {
      const engine = createEqEngine(audioRef.current, eqIndices, eqGains, eqAnalyserRef);
      eqEngineRef.current = engine;
      engine.connect();
      engine.setEnabled(eqEnabled, eqIndices, eqGains);
    }

    loadingRef.current = true;
    setIsLoading(true);
    try {
      const data = await apiService.getAudioUrl(song.videoId);
      if (!data?.url) throw new Error('No audio URL returned');
      audioRef.current.src = data.url;
      audioRef.current.volume = volumeRef.current;
      await audioRef.current.play();
      setCurrentSong(song);
      setIsPlaying(true);
      setIsLoading(false);
      loadingRef.current = false;
    } catch (err) {
      console.error('[Player] Failed to load audio:', err);
      setIsLoading(false);
      loadingRef.current = false;
      if (queue.length > 0) {
        playNextRef.current();
      }
    }
  };

  const playSong = (song, newQueue = null) => {
    if (newQueue) {
      originalQueueRef.current = [...newQueue];
      if (shuffle) {
        shuffledIndicesRef.current = shuffleArray(newQueue.map((_, i) => i));
        const shuffledQueue = shuffledIndicesRef.current.map(i => newQueue[i]);
        setQueue(shuffledQueue);
        const idx = shuffledQueue.findIndex(s => s.videoId === song.videoId);
        setCurrentIndex(idx >= 0 ? idx : 0);
      } else {
        setQueue(newQueue);
        const index = newQueue.findIndex(s => s.videoId === song.videoId);
        setCurrentIndex(index >= 0 ? index : 0);
      }
    }
    setProgress(0);
    loadAndPlay(song);
  };

  const togglePlay = () => {
    if (!audioRef.current) return;
    if (isPlaying) {
      commitStatsDeltaRef.current();
      audioRef.current.pause();
      setIsPlaying(false);
    } else {
      audioRef.current.play().then(() => setIsPlaying(true)).catch(console.error);
    }
  };

  const playNext = useCallback(() => {
    if (queue.length === 0) return;

    if (repeat === 'one') {
      setProgress(0);
      if (audioRef.current) {
        audioRef.current.currentTime = 0;
        audioRef.current.play().catch(console.error);
      }
      return;
    }

    if (currentIndex < queue.length - 1) {
      const nextIndex = currentIndex + 1;
      setCurrentIndex(nextIndex);
      setProgress(0);
      loadAndPlay(queue[nextIndex]);
    } else if (repeat === 'all') {
      setCurrentIndex(0);
      setProgress(0);
      loadAndPlay(queue[0]);
    }
  }, [queue, currentIndex, repeat]);

  playNextRef.current = playNext;

  const playPrevious = () => {
    if (currentIndex > 0) {
      const prevIndex = currentIndex - 1;
      setCurrentIndex(prevIndex);
      setProgress(0);
      loadAndPlay(queue[prevIndex]);
    }
  };

  const setQueueSongs = (songs, startIndex = 0) => {
    originalQueueRef.current = [...songs];
    let song;
    if (shuffle) {
      shuffledIndicesRef.current = shuffleArray(songs.map((_, i) => i));
      const shuffled = shuffledIndicesRef.current.map(i => songs[i]);
      setQueue(shuffled);
      setCurrentIndex(0);
      song = shuffled[0];
    } else {
      setQueue(songs);
      setCurrentIndex(startIndex);
      song = songs[startIndex];
    }
    setProgress(0);
    loadAndPlay(song);
  };

  const addToQueue = (song) => {
    const newQueue = [...queue, song];
    originalQueueRef.current = [...originalQueueRef.current, song];
    setQueue(newQueue);
  };

  const removeFromQueue = (index) => {
    const newQueue = queue.filter((_, i) => i !== index);
    if (!shuffle) {
      originalQueueRef.current = originalQueueRef.current.filter((_, i) => i !== index);
    } else {
      const shuffledIdx = shuffledIndicesRef.current[index];
      originalQueueRef.current = originalQueueRef.current.filter((_, i) => i !== shuffledIdx);
      shuffledIndicesRef.current = shuffledIndicesRef.current
        .filter(si => si !== shuffledIdx)
        .map(si => si > shuffledIdx ? si - 1 : si);
    }
    setQueue(newQueue);
    if (index === currentIndex) {
      if (newQueue.length > 0) {
        const newIndex = Math.min(index, newQueue.length - 1);
        setCurrentIndex(newIndex);
        loadAndPlay(newQueue[newIndex]);
      } else {
        setCurrentSong(null);
        setIsPlaying(false);
        if (audioRef.current) {
          audioRef.current.pause();
          audioRef.current.src = '';
        }
      }
    } else if (index < currentIndex) {
      setCurrentIndex(currentIndex - 1);
    }
  };

  const reorderQueue = (fromIndex, toIndex) => {
    if (shuffle) return;
    const newQueue = [...queue];
    const [moved] = newQueue.splice(fromIndex, 1);
    newQueue.splice(toIndex, 0, moved);
    setQueue(newQueue);

    const newOriginal = [...originalQueueRef.current];
    const [movedOrig] = newOriginal.splice(fromIndex, 1);
    newOriginal.splice(toIndex, 0, movedOrig);
    originalQueueRef.current = newOriginal;

    if (fromIndex === currentIndex) {
      setCurrentIndex(toIndex);
    } else if (fromIndex < currentIndex && toIndex >= currentIndex) {
      setCurrentIndex(currentIndex - 1);
    } else if (fromIndex > currentIndex && toIndex <= currentIndex) {
      setCurrentIndex(currentIndex + 1);
    }
  };

  const clearQueue = () => {
    originalQueueRef.current = [];
    shuffledIndicesRef.current = [];
    setQueue([]);
    setCurrentIndex(0);
    setCurrentSong(null);
    setIsPlaying(false);
    setProgress(0);
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.src = '';
    }
  };

  const seekTo = (time) => {
    setProgress(time);
    if (audioRef.current) {
      audioRef.current.currentTime = time;
    }
  };

  const changeVolume = (newVolume) => {
    setVolume(newVolume);
    if (audioRef.current) {
      audioRef.current.volume = newVolume;
    }
  };

  const toggleRepeat = () => {
    setRepeat(prev => prev === 'off' ? 'one' : prev === 'one' ? 'all' : 'off');
  };

  const toggleShuffle = () => {
    setShuffle(prev => {
      if (!prev) {
        shuffledIndicesRef.current = shuffleArray(originalQueueRef.current.map((_, i) => i));
        const shuffled = shuffledIndicesRef.current.map(i => originalQueueRef.current[i]);
        const currentVid = currentSong?.videoId;
        const foundIdx = shuffled.findIndex(s => s.videoId === currentVid);
        setQueue(shuffled);
        setCurrentIndex(foundIdx >= 0 ? foundIdx : 0);
      } else {
        setQueue([...originalQueueRef.current]);
        const currentVid = currentSong?.videoId;
        const foundIdx = originalQueueRef.current.findIndex(s => s.videoId === currentVid);
        setCurrentIndex(foundIdx >= 0 ? foundIdx : 0);
      }
      return !prev;
    });
  };

  const value = {
    currentSong,
    queue,
    currentIndex,
    isPlaying,
    isLoading,
    volume,
    progress,
    duration,
    repeat,
    shuffle,
    playSong,
    togglePlay,
    playNext,
    playPrevious,
    setQueueSongs,
    addToQueue,
    removeFromQueue,
    reorderQueue,
    clearQueue,
    showQueue,
    setShowQueue,
    showLyrics,
    setShowLyrics,
    hasLyrics,
    setHasLyrics,
    seekTo,
    changeVolume,
    setProgress,
    setDuration,
    setIsPlaying,
    toggleRepeat,
    setRepeat,
    toggleShuffle,
    setShuffle,
    playerExpanded,
    setPlayerExpanded,
    dragOffset,
    setDragOffset,
    isDragging,
    setIsDragging,
    minimizeOffset,
    setMinimizeOffset,
    userPresets,
    saveCurrentPreset,
    deleteUserPreset,
    eqEnabled,
    eqIndices,
    eqGains,
    setEqBand,
    addEqBand,
    removeEqBand,
    toggleEq,
    resetEq,
    applyPreset,
    eqAnalyserRef,
  };

  return (
    <PlayerContext.Provider value={value}>
      {children}
      <audio ref={audioRef} preload="none" />
    </PlayerContext.Provider>
  );
};
