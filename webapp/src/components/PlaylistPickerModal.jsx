import { useState } from 'react';
import { Plus, Music, X, Check } from 'lucide-react';
import { storage, playlistUtils } from '../utils/storage';
import { ArtImage } from './ArtImage';

export const PlaylistPickerModal = ({ song, onClose }) => {
  const [playlists, setPlaylists] = useState(() => storage.getPlaylists());
  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState('');
  const [addedId, setAddedId] = useState(null);

  const handleAdd = (pl) => {
    playlistUtils.addSongToPlaylist(pl.id, song);
    setAddedId(pl.id);
    setTimeout(() => { setAddedId(null); onClose(); }, 600);
  };

  const handleCreate = () => {
    if (!newName.trim()) return;
    const pl = playlistUtils.createPlaylist(newName);
    playlistUtils.addSongToPlaylist(pl.id, song);
    setNewName('');
    setShowCreate(false);
    setAddedId(pl.id);
    setTimeout(() => { setAddedId(null); onClose(); }, 600);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-scrim/60 animate-fadeIn" onClick={onClose}>
      <div
        className="bg-surface-container rounded-2xl w-full max-w-sm mx-4 shadow-2xl border border-outline-variant animate-scaleIn"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-outline-variant">
          <h3 className="text-lg font-semibold text-on-surface">Add to Playlist</h3>
          <button onClick={onClose} className="p-1 text-on-surface-variant hover:text-on-surface rounded-full hover:bg-surface-container-high transition-colors">
            <X size={20} />
          </button>
        </div>

        {/* Song preview */}
        <div className="flex items-center gap-3 px-5 py-3 bg-surface-container/80 border-b border-outline-variant">
          <ArtImage src={song.thumbnail} alt="" className="w-10 h-10 rounded object-cover" />
          <div className="min-w-0 flex-1">
            <p className="text-sm text-on-surface font-medium truncate">{song.title}</p>
            <p className="text-xs text-on-surface-variant truncate">{song.channelTitle}</p>
          </div>
        </div>

        {/* Create new */}
        <div className="px-3 pt-3">
          {showCreate ? (
            <div className="flex gap-2 mb-2">
              <input
                value={newName}
                onChange={e => setNewName(e.target.value)}
                placeholder="Playlist name..."
                className="flex-1 px-3 py-2 bg-surface-container-high text-on-surface text-sm rounded-lg focus:outline-none focus:ring-2 focus:ring-primary"
                onKeyDown={e => { if (e.key === 'Enter') handleCreate(); if (e.key === 'Escape') setShowCreate(false) }}
                autoFocus
              />
              <button onClick={handleCreate} className="px-3 py-2 bg-primary text-on-surface text-sm rounded-lg hover:bg-primary/80 transition-colors">Create</button>
              <button onClick={() => setShowCreate(false)} className="px-3 py-2 bg-surface-container-high text-on-surface text-sm rounded-lg hover:bg-surface-container-highest transition-colors">Cancel</button>
            </div>
          ) : (
            <button
              onClick={() => setShowCreate(true)}
              className="w-full flex items-center gap-3 px-3 py-2.5 text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high/50 rounded-lg transition-colors text-sm"
            >
              <Plus size={18} />
              Create new playlist
            </button>
          )}
        </div>

        {/* Playlist list */}
        <div className="max-h-64 overflow-y-auto px-3 pb-3 space-y-0.5">
          {playlists.length === 0 ? (
            <p className="text-outline text-xs text-center py-6">No playlists yet</p>
          ) : (
            playlists.map(pl => (
              <button
                key={pl.id}
                onClick={() => handleAdd(pl)}
                disabled={addedId === pl.id}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors text-left ${
                  addedId === pl.id
                    ? 'bg-primary/20 text-primary'
                    : 'text-on-surface hover:bg-surface-container-high/50 hover:text-on-surface'
                }`}
              >
                <div className="w-8 h-8 rounded flex items-center justify-center flex-shrink-0 overflow-hidden">
                  {addedId === pl.id ? (
                    <div className="w-full h-full bg-primary flex items-center justify-center"><Check size={16} /></div>
                  ) : pl.customThumbnail || pl.songs?.[0]?.thumbnail ? (
                    <ArtImage src={pl.customThumbnail || pl.songs?.[0]?.thumbnail} alt="" className="w-full h-full object-cover" />
                  ) : (
                    <div className="w-full h-full bg-gradient-to-br from-primary to-primary-container flex items-center justify-center"><Music size={14} className="text-on-surface" /></div>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm truncate">{pl.name}</p>
                  <p className="text-xs text-outline">{pl.songs.length} songs</p>
                </div>
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  );
};
