import { useState, useEffect } from 'react';
import { Plus, Play, Music } from 'lucide-react';
import { useNavigate } from '../context/NavigationContext';
import { storage, playlistUtils } from '../utils/storage';
import { ArtImage } from './ArtImage';

export const Playlists = () => {
  const [playlists, setPlaylists] = useState([]);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [newPlaylistName, setNewPlaylistName] = useState('');
  const [newPlaylistDesc, setNewPlaylistDesc] = useState('');
  const { navigate } = useNavigate();

  useEffect(() => {
    loadPlaylists();
  }, []);

  const loadPlaylists = () => {
    setPlaylists(storage.getPlaylists());
  };

  const handleCreatePlaylist = () => {
    if (!newPlaylistName.trim()) return;
    playlistUtils.createPlaylist(newPlaylistName, newPlaylistDesc);
    setNewPlaylistName('');
    setNewPlaylistDesc('');
    setShowCreateModal(false);
    loadPlaylists();
  };

  const handleOpenPlaylist = (playlist) => {
    navigate({ type: 'playlist', params: { id: playlist.id } });
  };

  const getPlaylistThumbnail = (playlist) => {
    return playlist.customThumbnail || playlist.songs?.[0]?.thumbnail || null;
  };

  return (
    <div className="p-6">
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-2xl font-bold text-on-surface">Your Playlists</h2>
        <button
          onClick={() => setShowCreateModal(true)}
          className="flex items-center gap-2 px-4 py-2 bg-primary text-on-surface rounded-full hover:bg-primary/80 transition-colors"
        >
          <Plus size={20} />
          Create Playlist
        </button>
      </div>

      {showCreateModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-surface-container rounded-2xl p-6 w-full max-w-md">
            <h3 className="text-xl font-bold text-on-surface mb-4">Create New Playlist</h3>
            <input
              type="text"
              value={newPlaylistName}
              onChange={(e) => setNewPlaylistName(e.target.value)}
              placeholder="Playlist name"
              className="w-full px-4 py-2 bg-surface-container-high text-on-surface rounded-lg mb-4 focus:outline-none focus:ring-2 focus:ring-primary"
            />
            <textarea
              value={newPlaylistDesc}
              onChange={(e) => setNewPlaylistDesc(e.target.value)}
              placeholder="Description (optional)"
              className="w-full px-4 py-2 bg-surface-container-high text-on-surface rounded-lg mb-4 focus:outline-none focus:ring-2 focus:ring-primary resize-none"
              rows={3}
            />
            <div className="flex gap-2 justify-end">
              <button
                onClick={() => setShowCreateModal(false)}
                className="px-4 py-2 bg-surface-container-high text-on-surface rounded-lg hover:bg-surface-container-highest transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleCreatePlaylist}
                className="px-4 py-2 bg-primary text-on-surface rounded-lg hover:bg-primary/80 transition-colors"
              >
                Create
              </button>
            </div>
          </div>
        </div>
      )}

      {playlists.length === 0 ? (
        <div className="text-center text-on-surface-variant py-12">
          <Music size={48} className="mx-auto mb-4 opacity-50" />
          <p className="text-lg mb-2">No playlists yet</p>
          <p className="text-sm">Create your first playlist to get started!</p>
        </div>
      ) : (
        <div className="grid gap-4">
          {playlists.map((playlist) => {
            const thumb = getPlaylistThumbnail(playlist);
            return (
              <div
                key={playlist.id}
                onClick={() => handleOpenPlaylist(playlist)}
                className="flex items-center gap-4 p-4 bg-surface-container/50 rounded-xl hover:bg-surface-container transition-colors cursor-pointer group"
              >
                {thumb ? (
                  <ArtImage src={thumb} alt={playlist.name} className="w-16 h-16 rounded-lg object-cover" />
                ) : (
                  <div className="w-16 h-16 bg-gradient-to-br from-primary to-primary-container rounded-lg flex items-center justify-center">
                    <Music size={32} className="text-on-surface" />
                  </div>
                )}
                <div className="flex-1 min-w-0">
                  <h3 className="font-semibold text-on-surface truncate">{playlist.name}</h3>
                  <p className="text-sm text-on-surface-variant">{playlist.songs.length} songs</p>
                  {playlist.description && (
                    <p className="text-xs text-outline truncate">{playlist.description}</p>
                  )}
                </div>
                <div className="opacity-0 group-hover:opacity-100 transition-opacity">
                  <Play size={20} className="text-on-surface-variant" />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
