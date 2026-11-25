import { reencodeCover } from '../services/albumArtService';

const STORAGE_KEYS = {
  PLAYLISTS: 'ym_playlists',
  LISTENING_HISTORY: 'ym_listening_history',
  PREFERENCES: 'ym_preferences',
  SIDEBAR_WIDTH: 'ym_sidebar_width',
  MISTRAL_API_KEY: 'ym_mistral_api_key',
  TOTAL_SONGS: 'ym_total_songs',
  PLAY_STATS: 'ym_play_stats',
};

export const storage = {
  getPlaylists: () => {
    const data = localStorage.getItem(STORAGE_KEYS.PLAYLISTS);
    return data ? JSON.parse(data) : [];
  },

  savePlaylists: (playlists) => {
    localStorage.setItem(STORAGE_KEYS.PLAYLISTS, JSON.stringify(playlists));
  },

  getListeningHistory: () => {
    const data = localStorage.getItem(STORAGE_KEYS.LISTENING_HISTORY);
    return data ? JSON.parse(data) : [];
  },

  saveListeningHistory: (history) => {
    localStorage.setItem(STORAGE_KEYS.LISTENING_HISTORY, JSON.stringify(history));
  },

  getTotalSongs: () => {
    const val = Number(localStorage.getItem(STORAGE_KEYS.TOTAL_SONGS));
    return Number.isFinite(val) && val > 0 ? val : 0;
  },

  getPreferences: () => {
    const data = localStorage.getItem(STORAGE_KEYS.PREFERENCES);
    return data ? JSON.parse(data) : { theme: 'dark', autoplay: true, filterExplicit: false, aiEnabled: true, aiRecommendations: true, artworkBackground: true, oledBackground: false };
  },

  savePreferences: (preferences) => {
    localStorage.setItem(STORAGE_KEYS.PREFERENCES, JSON.stringify(preferences));
  },

  getSidebarWidth: () => {
    const val = localStorage.getItem(STORAGE_KEYS.SIDEBAR_WIDTH);
    return val !== null ? Number(val) : null;
  },

  saveSidebarWidth: (width) => {
    localStorage.setItem(STORAGE_KEYS.SIDEBAR_WIDTH, String(width));
  },

  getMistralApiKey: () => {
    return localStorage.getItem(STORAGE_KEYS.MISTRAL_API_KEY) || '';
  },

  saveMistralApiKey: (key) => {
    if (key) {
      localStorage.setItem(STORAGE_KEYS.MISTRAL_API_KEY, key);
    } else {
      localStorage.removeItem(STORAGE_KEYS.MISTRAL_API_KEY);
    }
  },
};

export const playlistUtils = {
  createPlaylist: (name, description = '') => {
    const playlists = storage.getPlaylists();
    const newPlaylist = {
      id: Date.now().toString(),
      name,
      description,
      songs: [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    playlists.push(newPlaylist);
    storage.savePlaylists(playlists);
    window.dispatchEvent(new Event('playlists-changed'));
    return newPlaylist;
  },

  updatePlaylist: (id, updates) => {
    const playlists = storage.getPlaylists();
    const index = playlists.findIndex(p => p.id === id);
    if (index !== -1) {
      playlists[index] = { ...playlists[index], ...updates, updatedAt: new Date().toISOString() };
      storage.savePlaylists(playlists);
      window.dispatchEvent(new Event('playlists-changed'));
      return playlists[index];
    }
    return null;
  },

  deletePlaylist: (id) => {
    const playlists = storage.getPlaylists();
    const filtered = playlists.filter(p => p.id !== id);
    storage.savePlaylists(filtered);
    window.dispatchEvent(new Event('playlists-changed'));
  },

  // Mirrors the mobile setCoverImage: re-encodes the picked image to a square
  // JPEG 0.85 and stores it on the playlist (customThumbnail is the desktop
  // equivalent of the mobile cover file; it round-trips with the playlist).
  setCoverImage: async (id, dataUrl) => {
    const jpeg = await reencodeCover(dataUrl);
    if (!jpeg) return null;
    const playlists = storage.getPlaylists();
    const index = playlists.findIndex(p => p.id === id);
    if (index === -1) return null;
    playlists[index] = { ...playlists[index], customThumbnail: jpeg, updatedAt: new Date().toISOString() };
    storage.savePlaylists(playlists);
    window.dispatchEvent(new Event('playlists-changed'));
    return playlists[index];
  },

  // Mirrors deleting the mobile cover file: clears customThumbnail, keeping any
  // fallback to the first track's thumbnail.
  removeCoverImage: (id) => {
    const playlists = storage.getPlaylists();
    const index = playlists.findIndex(p => p.id === id);
    if (index === -1) return null;
    const { customThumbnail: _customThumbnail, ...rest } = playlists[index];
    playlists[index] = { ...rest, updatedAt: new Date().toISOString() };
    storage.savePlaylists(playlists);
    window.dispatchEvent(new Event('playlists-changed'));
    return playlists[index];
  },

  // Mirrors the mobile resolveThumbnailForTrack: fill in a missing thumbnail
  // (and optionally title/artist) from /api/song/<videoId>, persisting the
  // result back into the playlist. Resolves to the thumbnail URL (or '').
  resolveThumbnailForTrack: async (playlistId, song) => {
    if (!song?.videoId) return '';
    if (song.thumbnail) return song.thumbnail;
    const { apiService } = await import('../services/apiService');
    const details = await apiService.getSong(song.videoId).catch(() => null);
    const thumb = details?.thumbnail || '';
    if (!thumb) return '';
    const playlists = storage.getPlaylists();
    const index = playlists.findIndex(p => p.id === playlistId);
    if (index !== -1) {
      const songs = playlists[index].songs || [];
      const sIndex = songs.findIndex(s => s.videoId === song.videoId);
      if (sIndex !== -1) {
        songs[sIndex] = { ...songs[sIndex], thumbnail: thumb };
        if (!songs[sIndex].title && details?.title) songs[sIndex].title = details.title;
        playlists[index] = { ...playlists[index], songs, updatedAt: new Date().toISOString() };
        storage.savePlaylists(playlists);
        window.dispatchEvent(new Event('playlists-changed'));
      }
    }
    return thumb;
  },

  addSongToPlaylist: (playlistId, song) => {
    const playlists = storage.getPlaylists();
    const playlist = playlists.find(p => p.id === playlistId);
    if (playlist) {
      playlist.songs.push({ ...song, addedAt: new Date().toISOString() });
      playlist.updatedAt = new Date().toISOString();
      storage.savePlaylists(playlists);
      window.dispatchEvent(new Event('playlists-changed'));
      return playlist;
    }
    return null;
  },

  reorderPlaylistSongs: (playlistId, fromIndex, toIndex) => {
    const playlists = storage.getPlaylists();
    const playlist = playlists.find(p => p.id === playlistId);
    if (playlist) {
      const [moved] = playlist.songs.splice(fromIndex, 1);
      playlist.songs.splice(toIndex, 0, moved);
      playlist.updatedAt = new Date().toISOString();
      storage.savePlaylists(playlists);
      window.dispatchEvent(new Event('playlists-changed'));
      return playlist;
    }
    return null;
  },

  removeSongFromPlaylist: (playlistId, songId) => {
    const playlists = storage.getPlaylists();
    const playlist = playlists.find(p => p.id === playlistId);
    if (playlist) {
      playlist.songs = playlist.songs.filter(s => s.videoId !== songId);
      playlist.updatedAt = new Date().toISOString();
      storage.savePlaylists(playlists);
      window.dispatchEvent(new Event('playlists-changed'));
      return playlist;
    }
    return null;
  },
};

const EQ_STORAGE_KEY = 'ym_eq_settings';

export const eqStorage = {
  getSettings() {
    try {
      const data = localStorage.getItem(EQ_STORAGE_KEY);
      if (!data) return null;
      const parsed = JSON.parse(data);
      if (parsed && Array.isArray(parsed.indices) && Array.isArray(parsed.gains)) {
        return { indices: parsed.indices, gains: parsed.gains };
      }
      return null;
    } catch {
      return null;
    }
  },

  saveSettings(settings) {
    localStorage.setItem(EQ_STORAGE_KEY, JSON.stringify(settings));
  },

  clear() {
    localStorage.removeItem(EQ_STORAGE_KEY);
  },
};

const EQ_PRESETS_KEY = 'ym_eq_presets';

export const eqPresetStorage = {
  getPresets() {
    try {
      const data = localStorage.getItem(EQ_PRESETS_KEY);
      if (!data) return [];
      const parsed = JSON.parse(data);
      if (Array.isArray(parsed)) return parsed;
      return [];
    } catch {
      return [];
    }
  },

  savePreset(name, indices, gains) {
    const presets = this.getPresets();
    const existing = presets.findIndex(p => p.name === name);
    const preset = { name, indices, gains };
    if (existing !== -1) {
      presets[existing] = preset;
    } else {
      presets.push(preset);
    }
    localStorage.setItem(EQ_PRESETS_KEY, JSON.stringify(presets));
    window.dispatchEvent(new Event('eq-presets-changed'));
    return preset;
  },

  deletePreset(name) {
    const presets = this.getPresets().filter(p => p.name !== name);
    localStorage.setItem(EQ_PRESETS_KEY, JSON.stringify(presets));
    window.dispatchEvent(new Event('eq-presets-changed'));
  },

  renamePreset(oldName, newName) {
    const presets = this.getPresets();
    const preset = presets.find(p => p.name === oldName);
    if (preset) {
      preset.name = newName;
      localStorage.setItem(EQ_PRESETS_KEY, JSON.stringify(presets));
      window.dispatchEvent(new Event('eq-presets-changed'));
    }
  },
};

export const historyUtils = {
  addToHistory: (song) => {
    const history = storage.getListeningHistory();
    const existingIndex = history.findIndex(s => s.videoId === song.videoId);
    if (existingIndex === -1) {
      const total = storage.getTotalSongs() + 1;
      localStorage.setItem(STORAGE_KEYS.TOTAL_SONGS, String(total));
    }
    if (existingIndex !== -1) {
      history.splice(existingIndex, 1);
    }
    history.unshift({ ...song, playedAt: new Date().toISOString() });
    const maxHistory = 100;
    if (history.length > maxHistory) {
      history.splice(maxHistory);
    }
    storage.saveListeningHistory(history);
    window.dispatchEvent(new Event('history-changed'));
    return history;
  },

  clearHistory: () => {
    storage.saveListeningHistory([]);
    window.dispatchEvent(new Event('history-changed'));
  },

};

function artistNameOf(song) {
  return song.channelTitle || song.artists?.[0]?.name || '';
}

// Persistent listening stats, mirroring the mobile app's stats.plist:
//   { [videoId]: { plays, seconds, title, channelTitle, artists, thumbnail, album, duration } }
export const statsUtils = {
  getMap: () => {
    const data = localStorage.getItem(STORAGE_KEYS.PLAY_STATS);
    try {
      const parsed = JSON.parse(data);
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
      return {};
    }
  },

  _meta: (entry, song) => {
    entry.title = song.title || entry.title || '';
    const artist = artistNameOf(song);
    if (artist) {
      entry.channelTitle = artist;
      entry.artists = song.artists?.length ? song.artists : [{ name: artist }];
    }
    if (song.album) entry.album = song.album;
    if (song.thumbnail) entry.thumbnail = song.thumbnail;
    if (song.duration) entry.duration = Number(song.duration);
  },

  recordTrackPlay: (song) => {
    if (!song?.videoId) return;
    const map = statsUtils.getMap();
    const entry = map[song.videoId] || { plays: 0, seconds: 0 };
    entry.plays += 1;
    statsUtils._meta(entry, song);
    map[song.videoId] = entry;
    localStorage.setItem(STORAGE_KEYS.PLAY_STATS, JSON.stringify(map));
    window.dispatchEvent(new Event('stats-changed'));
  },

  addListenedSeconds: (song, seconds) => {
    if (!song?.videoId || !seconds || seconds <= 0) return;
    const map = statsUtils.getMap();
    const entry = map[song.videoId] || { plays: 0, seconds: 0 };
    entry.seconds = Number(entry.seconds || 0) + seconds;
    statsUtils._meta(entry, song);
    map[song.videoId] = entry;
    localStorage.setItem(STORAGE_KEYS.PLAY_STATS, JSON.stringify(map));
    window.dispatchEvent(new Event('stats-changed'));
  },

  clear: () => {
    localStorage.removeItem(STORAGE_KEYS.PLAY_STATS);
    window.dispatchEvent(new Event('stats-changed'));
  },

  entries: () => {
    const map = statsUtils.getMap();
    return Object.entries(map).map(([videoId, data]) => ({
      videoId,
      plays: Number(data.plays) || 0,
      seconds: Number(data.seconds) || 0,
      title: data.title || '',
      channelTitle: data.channelTitle || data.artists?.[0]?.name || '',
      thumbnail: data.thumbnail || '',
      album: data.album || '',
      duration: Number(data.duration) || 0,
    }));
  },

  mostPlayed: () => statsUtils.entries().sort((a, b) => {
    if (a.plays !== b.plays) return b.plays - a.plays;
    if (a.seconds !== b.seconds) return b.seconds - a.seconds;
    return a.title.localeCompare(b.title);
  }),

  topArtists: () => {
    const byArtist = {};
    for (const entry of statsUtils.entries()) {
      const name = entry.channelTitle || 'Unknown Artist';
      const agg = byArtist[name] || { name, plays: 0, seconds: 0 };
      agg.plays += entry.plays;
      agg.seconds += entry.seconds;
      byArtist[name] = agg;
    }
    return Object.values(byArtist).sort((a, b) => {
      if (a.seconds !== b.seconds) return b.seconds - a.seconds;
      return b.plays - a.plays;
    });
  },

  totalTime: () => statsUtils.entries().reduce((sum, e) => sum + e.seconds, 0),
  totalPlays: () => statsUtils.entries().reduce((sum, e) => sum + e.plays, 0),
};
