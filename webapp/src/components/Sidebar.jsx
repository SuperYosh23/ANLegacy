import { useState, useEffect } from 'react';
import { Plus, Music, Home, Library, Search, BarChart3, Settings, Play, Trash2, Edit3 } from 'lucide-react';
import { useNavigate } from '../context/NavigationContext';
import { storage, playlistUtils } from '../utils/storage';
import { ContextMenu } from './ContextMenu';
import { ArtImage } from './ArtImage';
import { Ripple } from './Ripple';

const navItems = [
  { id: 'home', label: 'Home', icon: Home },
  { id: 'search', label: 'Search', icon: Search },
  { id: 'library', label: 'Library', icon: Library },
  { id: 'stats', label: 'Stats', icon: BarChart3 },
  { id: 'settings', label: 'Settings', icon: Settings },
]

export const Sidebar = ({ activeTab, onTabChange, onNavigate, collapsed, dragging, width }) => {
  const [playlists, setPlaylists] = useState(() => storage.getPlaylists());
  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState('');
  const [cmPos, setCmPos] = useState(null);
  const [cmPlaylist, setCmPlaylist] = useState(null);
  const [renamingId, setRenamingId] = useState(null);
  const [renameName, setRenameName] = useState('');
  const { subPage, navigate } = useNavigate();
  const activePlaylistId = subPage?.type === 'playlist' ? subPage.params.id : null;

  const refresh = () => setPlaylists(storage.getPlaylists());

  useEffect(() => {
    window.addEventListener('playlists-changed', refresh);
    return () => window.removeEventListener('playlists-changed', refresh);
  }, []);

  const handleCreate = () => {
    if (!newName.trim()) return;
    playlistUtils.createPlaylist(newName);
    setNewName('');
    setShowCreate(false);
    refresh();
  };

  const handlePlaylistClick = (pl) => {
    navigate({ type: 'playlist', params: { id: pl.id } });
    onNavigate?.();
  };

  const handleContextMenu = (e, pl) => {
    e.preventDefault();
    setCmPlaylist(pl);
    setCmPos({ x: e.clientX, y: e.clientY });
  };

  const handlePlayPlaylist = () => {
    if (!cmPlaylist) return;
    navigate({ type: 'playlist', params: { id: cmPlaylist.id } });
    onNavigate?.();
  };

  const handleRenamePlaylist = () => {
    if (!cmPlaylist) return;
    setRenamingId(cmPlaylist.id);
    setRenameName(cmPlaylist.name);
  };

  const handleSaveRename = () => {
    if (!renameName.trim() || !renamingId) return;
    playlistUtils.updatePlaylist(renamingId, { name: renameName });
    setRenamingId(null);
    setRenameName('');
    refresh();
  };

  const handleDeletePlaylist = () => {
    if (!cmPlaylist) return;
    if (window.confirm(`Delete "${cmPlaylist.name}"?`)) {
      playlistUtils.deletePlaylist(cmPlaylist.id);
      refresh();
    }
  };

  const cmItems = [
    { label: 'Open', icon: <Play size={14} />, onClick: handlePlayPlaylist },
    { label: 'Rename', icon: <Edit3 size={14} />, onClick: handleRenamePlaylist },
    { separator: true },
    { label: 'Delete', icon: <Trash2 size={14} />, onClick: handleDeletePlaylist, danger: true },
  ];

  return (
    <div
      data-oled-chrome
      className="bg-surface-container-high border-r border-outline-variant flex flex-col overflow-hidden h-full"
      style={{ width, transition: dragging ? 'none' : 'width 0.2s ease-out' }}
    >
      <div className="border-b border-outline-variant min-h-[1px]" />

      {/* Nav links */}
      <nav className="p-2 space-y-0.5">
        {navItems.map((item) => {
          const Icon = item.icon
          return (
            <Ripple key={item.id} className="rounded-lg" slow>
              <button
                onClick={() => { onTabChange(item.id); navigate(null) }}
                className={`w-full flex items-center py-2.5 rounded-lg text-sm transition-colors ${
                  collapsed
                    ? 'justify-center'
                    : 'gap-3 px-3'
                } ${
                  activeTab === item.id && !activePlaylistId
                    ? 'bg-primary/20 text-primary'
                    : 'text-on-surface-variant hover:text-on-surface hover:bg-surface-container'
                }`}
                title={collapsed ? item.label : undefined}
              >
                <Icon size={18} />
                {!collapsed && <span>{item.label}</span>}
              </button>
            </Ripple>
          )
        })}
      </nav>

      {/* Playlists section */}
      <div className="flex-1 flex flex-col min-h-0 border-t border-outline-variant pt-3">
        {!collapsed && (
          <>
            <div className="flex items-center justify-between px-4 mb-2">
              <h3 className="text-xs font-semibold text-outline uppercase tracking-wider">
                Playlists
              </h3>
              <button
                onClick={() => setShowCreate(true)}
                className="shrink-0 p-1 text-on-surface-variant hover:text-on-surface hover:bg-surface-container rounded transition-colors"
                title="Create playlist"
              >
                <Plus size={16} />
              </button>
            </div>
            {showCreate && (
              <div className="flex gap-2 px-4 mb-2">
                <input
                  value={newName}
                  onChange={e => setNewName(e.target.value)}
                  placeholder="Name..."
                  className="flex-1 px-2 py-1 bg-surface-container text-on-surface text-xs rounded focus:outline-none focus:ring-1 focus:ring-primary"
                  onKeyDown={e => { if (e.key === 'Enter') handleCreate(); if (e.key === 'Escape') setShowCreate(false) }}
                  autoFocus
                />
              </div>
            )}
          </>
        )}

        <div className={`flex-1 overflow-y-auto ${collapsed ? 'px-1' : 'px-2'} space-y-0.5`}>
          {playlists.length === 0 ? (
            !collapsed && (
              <p className="text-outline text-xs text-center py-4">
                No playlists yet
              </p>
            )
          ) : (
            playlists.map((pl) => {
              const thumb = pl.customThumbnail || pl.songs?.[0]?.thumbnail || null;
              const isRenaming = renamingId === pl.id;
              return (
                <div key={pl.id}>
                  {isRenaming ? (
                    <div className="flex gap-2 px-3 py-1.5">
                      <input
                        value={renameName}
                        onChange={e => setRenameName(e.target.value)}
                        placeholder="Name..."
                        className="flex-1 px-2 py-1 bg-surface-container text-on-surface text-xs rounded focus:outline-none focus:ring-1 focus:ring-primary"
                        onKeyDown={e => {
                          if (e.key === 'Enter') handleSaveRename();
                          if (e.key === 'Escape') setRenamingId(null);
                        }}
                        autoFocus
                      />
                    </div>
                  ) : (
                    <Ripple className="rounded-lg" slow>
                    <button
                      onContextMenu={(e) => handleContextMenu(e, pl)}
                      onClick={() => handlePlaylistClick(pl)}
                      className={`w-full flex items-center py-2 rounded-lg transition-colors group ${
                        collapsed ? 'justify-center' : 'gap-3 px-3 text-left'
                      } ${
                        activePlaylistId === pl.id ? 'bg-primary/20 text-primary' : 'hover:bg-surface-container'
                      }`}
                      title={collapsed ? pl.name : undefined}
                    >
                      {thumb ? (
                        <ArtImage src={thumb} alt="" className={`${collapsed ? 'w-8 h-8' : 'w-6 h-6'} rounded object-cover shrink-0`} />
                      ) : (
                        <div className={`${collapsed ? 'w-8 h-8' : 'w-6 h-6'} rounded bg-gradient-to-br from-primary to-primary-container flex items-center justify-center shrink-0`}>
                          <Music size={collapsed ? 16 : 12} className="text-on-surface" />
                        </div>
                      )}
                      {!collapsed && (
                        <div className="flex-1 min-w-0">
                          <p className="text-sm text-on-surface truncate group-hover:text-on-surface">{pl.name}</p>
                          <p className="text-xs text-outline">{pl.songs.length} songs</p>
                        </div>
                      )}
                    </button>
                    </Ripple>
                  )}
                </div>
              );
            })
          )}
        </div>
      </div>
      {cmPos && cmPlaylist && (
        <ContextMenu
          items={cmItems}
          position={cmPos}
          onClose={() => { setCmPos(null); setCmPlaylist(null); }}
        />
      )}
    </div>
  )
}
