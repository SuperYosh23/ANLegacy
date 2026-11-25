import { useState, useEffect, useCallback } from 'react';
import { Library as LibraryIcon, ListMusic, Music2, MicVocal, Disc3, Plus, Search, Play, Shuffle, Trash2, ChevronRight, X } from 'lucide-react';
import { usePlayer } from '../context/PlayerContext';
import { useNavigate } from '../context/NavigationContext';
import { storage, playlistUtils } from '../utils/storage';
import { ArtImage } from './ArtImage';
import { ArtistAvatar } from './ArtistAvatar';

const TABS = [
  { id: 'playlists', label: 'Playlists', icon: ListMusic },
  { id: 'songs', label: 'Songs', icon: Music2 },
  { id: 'artists', label: 'Artists', icon: MicVocal },
  { id: 'albums', label: 'Albums', icon: Disc3 },
];

function artistName(song) {
  return song.channelTitle || song.artists?.[0]?.name || 'Unknown Artist';
}

function albumName(song) {
  return song.album || 'Unknown Album';
}

function formatDuration(seconds) {
  const s = Math.floor(seconds);
  const m = Math.floor(s / 60);
  return `${m}:${String(s % 60).padStart(2, '0')}`;
}

function bucketSongs(songs) {
  const map = new Map();
  for (const song of songs) {
    if (!song?.videoId) continue;
    map.set(song.videoId, song);
  }
  return [...map.values()];
}

function buildArtists(songs) {
  const map = {};
  for (const song of songs) {
    const name = artistName(song);
    (map[name] = map[name] || { name, tracks: [] }).tracks.push(song);
  }
  return Object.values(map).sort((a, b) => a.name.localeCompare(b.name));
}

function buildAlbums(songs) {
  const map = {};
  for (const song of songs) {
    const artist = artistName(song);
    const album = albumName(song);
    const key = `${artist.toLowerCase()}|${album.toLowerCase()}`;
    const bucket = (map[key] = map[key] || { name: album, artist, tracks: [] });
    bucket.tracks.push(song);
  }
  return Object.values(map).sort((a, b) => a.name.localeCompare(b.name));
}

function SongRow({ song, onClick, sub, trailing }) {
  return (
    <button
      onClick={onClick}
      className="w-full flex items-center gap-3 p-2.5 hover:bg-surface-container-high/50 transition-all text-left group"
      title={song.title}
    >
      <ArtImage
        src={song.thumbnail}
        alt={song.title}
        className="w-12 h-12 rounded-xl object-cover shadow-md shrink-0"
      />
      <div className="flex-1 min-w-0">
        <p className="text-on-surface font-medium truncate">{song.title || 'Unknown Song'}</p>
        <p className="text-xs text-on-surface-variant truncate">{sub}</p>
      </div>
      {trailing}
    </button>
  );
}

export const Library = () => {
  const [tab, setTab] = useState('playlists');
  const [playlists, setPlaylists] = useState(() => storage.getPlaylists());
  const [songs, setSongs] = useState([]);
  const [query, setQuery] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState('');
  const { playSong, setQueueSongs, setRepeat, setShuffle } = usePlayer();
  const { navigate } = useNavigate();

  const refresh = useCallback(() => {
    setPlaylists(storage.getPlaylists());
    setSongs(bucketSongs([
      ...storage.getPlaylists().flatMap(p => p.songs || []),
      ...storage.getListeningHistory(),
    ]));
  }, []);

  useEffect(() => {
    refresh();
    window.addEventListener('playlists-changed', refresh);
    window.addEventListener('history-changed', refresh);
    return () => {
      window.removeEventListener('playlists-changed', refresh);
      window.removeEventListener('history-changed', refresh);
    };
  }, [refresh]);

  const filtered = query.trim()
    ? songs.filter(s => {
        const q = query.trim().toLowerCase();
        return s.title?.toLowerCase().includes(q)
          || (s.channelTitle || s.artists?.[0]?.name || '').toLowerCase().includes(q);
      })
    : songs;

  const handleCreate = () => {
    if (!newName.trim()) return;
    playlistUtils.createPlaylist(newName.trim());
    setNewName('');
    setShowCreate(false);
  };

  const handleDelete = (playlist) => {
    if (window.confirm(`Delete "${playlist.name}"?`)) {
      playlistUtils.deletePlaylist(playlist.id);
    }
  };

  const handlePlaySong = (song) => {
    playSong(song, filtered);
  };

  const handlePlayAll = () => {
    if (filtered.length > 0) {
      setShuffle(false);
      setRepeat('all');
      setQueueSongs(filtered, 0);
    }
  };

  const handleShuffleAll = () => {
    if (filtered.length > 0) {
      setShuffle(true);
      setRepeat('all');
      const s = [...filtered].sort(() => Math.random() - 0.5);
      setQueueSongs(s, 0);
    }
  };

  const handleOpenBucket = (name, tracks) => {
    navigate({ type: 'library-songs', params: { title: name, tracks } });
  };

  const artists = buildArtists(songs);
  const albums = buildAlbums(songs);

  return (
    <div className="p-6 animate-fadeIn">
      <h2 className="text-2xl font-bold text-on-surface mb-6 flex items-center gap-2">
        <LibraryIcon size={24} />
        Library
      </h2>

      {/* Segmented tabs */}
      <div className="flex items-center justify-between mb-6">
        <div className="bg-surface-container rounded-xl p-1 flex gap-1">
          {TABS.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              onClick={() => setTab(id)}
              className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm transition-all ${
                tab === id
                  ? 'bg-surface-container-high text-on-surface shadow-sm'
                  : 'text-on-surface-variant hover:text-on-surface'
              }`}
            >
              <Icon size={16} />
              {label}
            </button>
          ))}
        </div>

        {tab === 'songs' && songs.length > 0 && (
          <div className="flex gap-2">
            <button
              onClick={handleShuffleAll}
              className="flex items-center gap-2 px-4 py-2 bg-surface-container-high text-on-surface rounded-lg hover:bg-surface-container-highest transition-colors"
            >
              <Shuffle size={16} />
              Shuffle
            </button>
            <button
              onClick={handlePlayAll}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-on-surface rounded-lg hover:bg-primary/80 transition-colors"
            >
              <Play size={16} />
              Play All
            </button>
          </div>
        )}
      </div>

      {tab === 'playlists' && (
        <div>
          {!showCreate ? (
            <button
              onClick={() => setShowCreate(true)}
              className="flex items-center gap-2 px-4 py-2 bg-surface-container-high text-on-surface rounded-lg hover:bg-surface-container-highest transition-colors mb-4"
            >
              <Plus size={16} />
              New Playlist
            </button>
          ) : (
            <div className="flex items-center gap-2 mb-4">
              <input
                value={newName}
                onChange={e => setNewName(e.target.value)}
                placeholder="Playlist name..."
                autoFocus
                onKeyDown={e => { if (e.key === 'Enter') handleCreate(); if (e.key === 'Escape') { setShowCreate(false); setNewName(''); } }}
                className="flex-1 max-w-xs px-3 py-2 bg-surface-container text-on-surface text-sm rounded-lg focus:outline-none focus:ring-2 focus:ring-primary"
              />
              <button
                onClick={handleCreate}
                className="px-4 py-2 bg-primary text-on-surface rounded-lg hover:bg-primary/80 transition-colors"
              >
                Create
              </button>
              <button
                onClick={() => { setShowCreate(false); setNewName(''); }}
                className="p-2 text-on-surface-variant hover:text-on-surface transition-colors"
              >
                <X size={18} />
              </button>
            </div>
          )}

          {playlists.length === 0 ? (
            <p className="text-on-surface-variant text-sm">No playlists yet. Tap + to create one.</p>
          ) : (
            <div className="bg-surface-container/30 rounded-2xl divide-y divide-outline-variant/20 overflow-hidden">
              {playlists.map(playlist => {
                const thumb = playlist.customThumbnail || playlist.songs?.[0]?.thumbnail || null;
                return (
                  <div
                    key={playlist.id}
                    className="flex items-center gap-3 p-2.5 hover:bg-surface-container-high/50 transition-all group"
                  >
                    <button
                      onClick={() => navigate({ type: 'playlist', params: { id: playlist.id } })}
                      className="flex items-center gap-3 flex-1 min-w-0 text-left"
                    >
                      {thumb ? (
                        <ArtImage src={thumb} alt="" className="w-14 h-14 rounded-xl object-cover shadow-md shrink-0" />
                      ) : (
                        <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-primary to-primary-container flex items-center justify-center shrink-0">
                          <ListMusic size={22} className="text-on-surface" />
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
                    <button
                      onClick={() => handleDelete(playlist)}
                      className="p-2 text-on-surface-variant hover:text-error opacity-0 group-hover:opacity-100 transition-all"
                      title="Delete playlist"
                    >
                      <Trash2 size={18} />
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {tab === 'songs' && (
        <div>
          <div className="relative mb-4 max-w-sm">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-outline" size={16} />
            <input
              value={query}
              onChange={e => setQuery(e.target.value)}
              placeholder="Search songs"
              className="w-full pl-9 pr-4 py-2 bg-surface-container text-on-surface text-sm rounded-full focus:outline-none focus:ring-2 focus:ring-primary"
            />
          </div>
          {filtered.length === 0 ? (
            <p className="text-on-surface-variant text-sm">
              {query.trim() ? 'No songs match your search.' : 'No songs in your library yet.'}
            </p>
          ) : (
            <div className="bg-surface-container/30 rounded-2xl divide-y divide-outline-variant/20 overflow-hidden">
              {filtered.map(song => (
                <SongRow
                  key={song.videoId}
                  song={song}
                  onClick={() => handlePlaySong(song)}
                  sub={`${artistName(song)}${song.duration > 0 ? `   ${formatDuration(song.duration)}` : ''}`}
                  trailing={
                    <span className="p-2.5 rounded-full bg-primary text-on-primary opacity-0 group-hover:opacity-100 transition-opacity">
                      <Play size={16} fill="currentColor" />
                    </span>
                  }
                />
              ))}
            </div>
          )}
        </div>
      )}

      {tab === 'artists' && (
        <div>
          {artists.length === 0 ? (
            <p className="text-on-surface-variant text-sm">No artists in your library yet.</p>
          ) : (
            <div className="bg-surface-container/30 rounded-2xl divide-y divide-outline-variant/20 overflow-hidden">
              {artists.map(bucket => {
                const thumb = bucket.tracks[0]?.thumbnail;
                return (
                  <button
                    key={bucket.name}
                    onClick={() => handleOpenBucket(bucket.name, bucket.tracks)}
                    className="w-full flex items-center gap-3 p-2.5 hover:bg-surface-container-high/50 transition-all text-left group"
                  >
                    {thumb ? (
                      <ArtistAvatar name={bucket.name} fallbackThumb={thumb} className="w-14 h-14 rounded-full object-cover shadow-md shrink-0" />
                    ) : (
                      <div className="w-14 h-14 rounded-full bg-gradient-to-br from-secondary to-secondary-container flex items-center justify-center shrink-0">
                        <MicVocal size={22} className="text-on-surface" />
                      </div>
                    )}
                    <div className="flex-1 min-w-0">
                      <p className="text-on-surface font-medium truncate">{bucket.name}</p>
                      <p className="text-xs text-on-surface-variant">
                        {bucket.tracks.length} song{bucket.tracks.length === 1 ? '' : 's'}
                      </p>
                    </div>
                    <ChevronRight size={18} className="text-outline shrink-0" />
                  </button>
                );
              })}
            </div>
          )}
        </div>
      )}

      {tab === 'albums' && (
        <div>
          {albums.length === 0 ? (
            <p className="text-on-surface-variant text-sm">No albums in your library yet.</p>
          ) : (
            <div className="bg-surface-container/30 rounded-2xl divide-y divide-outline-variant/20 overflow-hidden">
              {albums.map(bucket => {
                const thumb = bucket.tracks[0]?.thumbnail;
                return (
                  <button
                    key={`${bucket.artist}|${bucket.name}`}
                    onClick={() => handleOpenBucket(bucket.name, bucket.tracks)}
                    className="w-full flex items-center gap-3 p-2.5 hover:bg-surface-container-high/50 transition-all text-left group"
                  >
                    {thumb ? (
                      <ArtImage src={thumb} alt="" className="w-14 h-14 rounded-xl object-cover shadow-md shrink-0" />
                    ) : (
                      <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-tertiary to-tertiary-container flex items-center justify-center shrink-0">
                        <Disc3 size={22} className="text-on-surface" />
                      </div>
                    )}
                    <div className="flex-1 min-w-0">
                      <p className="text-on-surface font-medium truncate">{bucket.name}</p>
                      <p className="text-xs text-on-surface-variant truncate">
                        {bucket.artist}   {bucket.tracks.length} song{bucket.tracks.length === 1 ? '' : 's'}
                      </p>
                    </div>
                    <ChevronRight size={18} className="text-outline shrink-0" />
                  </button>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
};