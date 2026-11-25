import { useState, useEffect, useRef } from 'react';
import { ArrowLeft, Play, Shuffle, Music, Trash2, Edit2, Camera, Download } from 'lucide-react';
import { usePlayer } from '../context/PlayerContext';
import { useNavigate } from '../context/NavigationContext';
import { storage, playlistUtils } from '../utils/storage';
import { youtubeScraperService } from '../services/youtubeScraper';
import { ArtImage } from './ArtImage';
import { getBestThumbnail } from '../utils/thumbnail';

export const PlaylistPage = () => {
  const { subPage, navigate, navigateBack } = useNavigate();
  const { playSong, setQueueSongs, currentSong, setRepeat, setShuffle } = usePlayer();
  const [playlist, setPlaylist] = useState(null);
  const [editing, setEditing] = useState(false);
  const [editName, setEditName] = useState('');
  const dragIndexRef = useRef(null);
  const [dragOverIndex, setDragOverIndex] = useState(null);
  const fileInputRef = useRef(null);
  const [downloading, setDownloading] = useState(false);

  useEffect(() => {
    if (subPage?.params?.id) {
      const p = storage.getPlaylists().find(pl => pl.id === subPage.params.id);
      setPlaylist(p);
      if (p) setEditName(p.name);
    }
  }, [subPage?.params?.id]);

  if (!playlist) return (
    <div className="p-6">
      <button onClick={navigateBack} className="flex items-center gap-2 text-on-surface-variant hover:text-on-surface mb-6">
        <ArrowLeft size={20} /> Back
      </button>
      <p className="text-on-surface-variant text-center py-8">Playlist not found</p>
    </div>
  );

  const openArtist = (name, browseId, thumb) =>
    navigate({ type: 'artist', params: { name, artistId: browseId, thumbnail: thumb } });

  const handlePlayAll = () => {
    if (playlist.songs.length > 0) {
      setShuffle(false);
      setRepeat('all');
      setQueueSongs(playlist.songs, 0);
    }
  };

  const handleShuffle = () => {
    if (playlist.songs.length > 0) {
      setShuffle(true);
      setRepeat('all');
      const s = [...playlist.songs].sort(() => Math.random() - 0.5);
      setQueueSongs(s, 0);
    }
  };

  const handlePlaySong = (song) => {
    playSong(song, playlist.songs);
  };

  const handleRemoveSong = (songId) => {
    playlistUtils.removeSongFromPlaylist(playlist.id, songId);
    const updated = storage.getPlaylists().find(p => p.id === playlist.id);
    setPlaylist(updated);
  };

  const handleSaveEdit = () => {
    if (!editName.trim()) return;
    playlistUtils.updatePlaylist(playlist.id, { name: editName });
    setPlaylist({ ...playlist, name: editName });
    setEditing(false);
  };

  const handleDelete = () => {
    if (window.confirm('Delete this playlist?')) {
      playlistUtils.deletePlaylist(playlist.id);
      navigateBack();
    }
  };

  const handleUploadThumbnail = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = async (ev) => {
      const dataUrl = ev.target.result;
      const updated = await playlistUtils.setCoverImage(playlist.id, dataUrl);
      if (updated) setPlaylist(updated);
      if (fileInputRef.current) fileInputRef.current.value = '';
    };
    reader.readAsDataURL(file);
  };

  const handleRemoveThumbnail = () => {
    const updated = playlistUtils.removeCoverImage(playlist.id);
    if (updated) setPlaylist(updated);
  };

  const handleDownloadAll = async () => {
    if (!playlist.songs.length || downloading) return;
    setDownloading(true);
    try {
      const songs = playlist.songs.map(s => ({
        videoId: s.videoId,
        title: s.title,
        artist: s.channelTitle || '',
        album: s.album || '',
      }));
      const res = await fetch('/api/download-playlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: playlist.name, songs }),
      });
      if (!res.ok) throw new Error('Server error');
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${playlist.name}.zip`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 30000);
    } catch (err) {
      console.error('Playlist download failed:', err);
    } finally {
      setDownloading(false);
    }
  };

  const thumbnail = playlist.customThumbnail || getBestThumbnail(playlist.songs?.[0]?.thumbnail) || null;

  return (
    <div className="p-6 animate-fadeIn">

      <div className="flex items-center gap-6 mb-8 animate-slideDown">
        <div className="relative group flex-shrink-0">
          {thumbnail ? (
            <img key={playlist.customThumbnail ? 'custom' : 'auto'} src={thumbnail} alt={playlist.name} className="w-40 h-40 rounded-xl object-cover shadow-lg" />
          ) : (
            <div className="w-40 h-40 bg-gradient-to-br from-primary to-primary-container rounded-xl flex items-center justify-center">
              <Music size={64} className="text-on-surface/60" />
            </div>
          )}
          <div className="absolute inset-0 rounded-xl bg-scrim/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-2">
            <button
              onClick={() => fileInputRef.current?.click()}
              className="p-2 bg-surface-container/80 rounded-full hover:bg-surface-container-high transition-colors"
              title="Upload image"
            >
              <Camera size={20} />
            </button>
            {playlist.customThumbnail && (
              <button
                onClick={handleRemoveThumbnail}
                className="p-2 bg-red-700 text-white rounded-full hover:bg-red-800 transition-colors"
                title="Remove custom image"
              >
                <Trash2 size={20} />
              </button>
            )}
          </div>
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={handleUploadThumbnail}
          />
        </div>
        <div className="flex-1 min-w-0">
          {editing ? (
            <div className="flex gap-2 items-center mb-2">
              <input
                value={editName}
                onChange={e => setEditName(e.target.value)}
                className="bg-surface-container-high text-on-surface px-3 py-1 rounded text-2xl font-bold"
                autoFocus
              />
              <button onClick={handleSaveEdit} className="px-3 py-1 bg-primary text-on-surface rounded hover:bg-primary/80">Save</button>
              <button onClick={() => setEditing(false)} className="px-3 py-1 bg-surface-container-high text-on-surface rounded hover:bg-surface-container-highest">Cancel</button>
            </div>
          ) : (
            <h1 className="text-3xl font-bold text-on-surface mb-2">{playlist.name}</h1>
          )}
          <p className="text-on-surface-variant mb-1">{playlist.songs.length} songs</p>
          {playlist.description && <p className="text-outline text-sm mb-2">{playlist.description}</p>}
          <div className="flex gap-3 mt-4">
            <button onClick={handlePlayAll} className="flex items-center gap-2 px-6 py-2 bg-primary text-on-surface rounded-full hover:bg-primary/80">
              <Play size={18} /> Play All
            </button>
            <button onClick={handleShuffle} className="flex items-center gap-2 px-6 py-2 bg-surface-container-high text-on-surface rounded-full hover:bg-surface-container-highest">
              <Shuffle size={18} /> Shuffle
            </button>
            <button
              onClick={() => setEditing(true)}
              className="p-2 bg-surface-container-high text-on-surface rounded-full hover:bg-surface-container-highest"
              title="Edit"
            >
              <Edit2 size={18} />
            </button>
            <button
              onClick={handleDelete}
              className="p-2 bg-red-700 text-white rounded-full hover:bg-red-800"
              title="Delete"
            >
              <Trash2 size={18} />
            </button>
            <button
              onClick={handleDownloadAll}
              disabled={downloading || playlist.songs.length === 0}
              className="p-2 bg-surface-container-high text-on-surface rounded-full hover:bg-surface-container-highest disabled:opacity-50 disabled:cursor-not-allowed"
              title={downloading ? 'Downloading...' : 'Download all as ZIP'}
            >
              <Download size={18} />
            </button>
          </div>
        </div>
      </div>

      <div className="space-y-2">
        {playlist.songs.length === 0 ? (
          <p className="text-on-surface-variant text-center py-8">No songs in this playlist</p>
        ) : (
          playlist.songs.map((song, i) => (
            <div
              key={song.videoId}
              draggable
              onDragStart={() => { dragIndexRef.current = i; setDragOverIndex(i); }}
              onDragOver={(e) => { e.preventDefault(); setDragOverIndex(i); }}
              onDrop={() => {
                const from = dragIndexRef.current;
                if (from !== null && from !== i) {
                  playlistUtils.reorderPlaylistSongs(playlist.id, from, i);
                  const updated = storage.getPlaylists().find(p => p.id === playlist.id);
                  setPlaylist(updated);
                }
                dragIndexRef.current = null;
                setDragOverIndex(null);
              }}
              onDragEnd={() => {
                dragIndexRef.current = null;
                setDragOverIndex(null);
              }}
              className={`flex items-center gap-4 p-3 rounded-xl transition-colors group cursor-pointer animate-slideUp ${
                currentSong?.videoId === song.videoId ? 'bg-primary/20' : 'bg-surface-container/50 hover:bg-surface-container'
              } ${dragOverIndex === i ? 'ring-2 ring-primary' : ''}`}
              style={{ animationDelay: `${i * 0.04}s`, animationFillMode: 'backwards' }}
              onClick={() => handlePlaySong(song)}
            >
              <ArtImage src={song.thumbnail} alt="" className="w-12 h-12 rounded object-cover" />
              <div className="flex-1 min-w-0">
                <p className="text-on-surface font-medium truncate">{song.title}</p>
                <p className="text-on-surface-variant text-sm truncate">
                  <span
                    onClick={e => { e.stopPropagation(); openArtist(song.channelTitle, song.channelId, song.thumbnail); }}
                    className="cursor-pointer hover:text-on-surface"
                  >
                    {song.channelTitle}
                  </span>
                  {song.album && <span className="text-outline"> · {song.album}</span>}
                </p>
              </div>
              <span className="text-outline text-sm">
                {youtubeScraperService.formatDuration(song.duration)}
              </span>
              <div className="opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                <button
                  onClick={(e) => { e.stopPropagation(); handlePlaySong(song); }}
                  className="p-2 bg-primary text-on-surface rounded-full hover:bg-primary/80"
                >
                  <Play size={14} />
                </button>
                <button
                  onClick={(e) => { e.stopPropagation(); handleRemoveSong(song.videoId); }}
                  className="p-2 bg-red-700 text-white rounded-full hover:bg-red-800"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
