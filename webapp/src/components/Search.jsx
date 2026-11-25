import { useState, useEffect, useMemo } from 'react';
import { Search as SearchIcon, Music, Play, User, Disc3, Clock, Plus, SlidersHorizontal, X } from 'lucide-react';
import { usePlayer } from '../context/PlayerContext';
import { useNavigate } from '../context/NavigationContext';
import { youtubeScraperService } from '../services/youtubeScraper';
import { PlaylistPickerModal } from './PlaylistPickerModal';
import { LoadingIndicator } from './LoadingIndicator';
import { ArtImage } from './ArtImage';
import { storage } from '../utils/storage';

function parseDurationInput(text) {
  if (!text) return null;
  const t = text.trim();
  if (!t) return null;
  if (t.includes(':')) {
    const parts = t.split(':').map(Number);
    if (parts.length === 2 && !isNaN(parts[0]) && !isNaN(parts[1])) return parts[0] * 60 + parts[1];
    if (parts.length === 3 && !isNaN(parts[0]) && !isNaN(parts[1]) && !isNaN(parts[2])) return parts[0] * 3600 + parts[1] * 60 + parts[2];
    return null;
  }
  const n = Number(t);
  return isNaN(n) ? null : n;
}

export const Search = ({ searchQuery, setSearchQuery }) => {
  const [results, setResults] = useState({ songs: [], albums: [] });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState('songs');
  const [pickerSong, setPickerSong] = useState(null);
  const [showFilters, setShowFilters] = useState(false);
  const [filterDurationMin, setFilterDurationMin] = useState('');
  const [filterDurationMax, setFilterDurationMax] = useState('');
  const [filterArtist, setFilterArtist] = useState('');
  const [filterAlbum, setFilterAlbum] = useState('');
  const { playSong, addToQueue } = usePlayer();
  const { navigate } = useNavigate();

  useEffect(() => {
    if (!searchQuery.trim()) {
      setResults({ songs: [], albums: [] });
      return
    }
    let cancelled = false
    setLoading(true)
    setError('')
    const filterExplicit = storage.getPreferences().filterExplicit || false
    youtubeScraperService.searchAll(searchQuery, filterExplicit)
      .then(data => { if (!cancelled) setResults(data) })
      .catch(err => { if (!cancelled) { console.error('Search failed:', err); setError('Could not reach the music backend. Make sure the Python server is running on port 3614.') } })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [searchQuery])

  useEffect(() => {
    const tabOrder = ['songs', 'albums']
    if (!tabOrder.includes(activeTab) || (results[activeTab]?.length || 0) === 0) {
      const first = tabOrder.find(t => (results[t]?.length || 0) > 0)
      if (first) setActiveTab(first)
    }
  }, [results])

  useEffect(() => {
    setFilterDurationMin('');
    setFilterDurationMax('');
    setFilterArtist('');
    setFilterAlbum('');
    setShowFilters(false);
  }, [searchQuery]);

  const hasActiveFilters = filterDurationMin || filterDurationMax || filterArtist || filterAlbum;

  const clearFilters = () => {
    setFilterDurationMin('');
    setFilterDurationMax('');
    setFilterArtist('');
    setFilterAlbum('');
  };

  const filteredSongs = useMemo(() => {
    if (activeTab !== 'songs') return results.songs;
    let list = results.songs;
    const dMin = parseDurationInput(filterDurationMin);
    const dMax = parseDurationInput(filterDurationMax);
    if (dMin !== null) list = list.filter(s => (s.duration || 0) >= dMin);
    if (dMax !== null) list = list.filter(s => (s.duration || 0) <= dMax);
    if (filterArtist.trim()) {
      const q = filterArtist.trim().toLowerCase();
      list = list.filter(s => (s.channelTitle || '').toLowerCase().includes(q));
    }
    if (filterAlbum.trim()) {
      const q = filterAlbum.trim().toLowerCase();
      list = list.filter(s => (s.album || '').toLowerCase().includes(q));
    }
    return list;
  }, [results.songs, activeTab, filterDurationMin, filterDurationMax, filterArtist, filterAlbum]);

  const handlePlaySong = (song) => {
    playSong(song, filteredSongs);
  };

  const handleAddToQueue = (song) => {
    addToQueue(song);
  };

  const handleAddToPlaylist = (song) => {
    setPickerSong(song);
  };

  const openArtist = (name, browseId, thumb) =>
    navigate({ type: 'artist', params: { name, artistId: browseId, thumbnail: thumb } });

  const openAlbum = (album) => navigate({ type: 'album', params: album });

  const formatDuration = (s) => {
    if (!s) return '';
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return `${m}:${sec.toString().padStart(2, '0')}`;
  };

  const tabs = [
    { id: 'songs', label: 'Songs', icon: Music, count: results.songs.length },
    { id: 'albums', label: 'Albums', icon: Disc3, count: results.albums.length },
  ];

  const hasResults = tabs.some(t => t.count > 0);
  const showFiltersForTab = activeTab === 'songs' && results.songs.length > 0;

  if (!searchQuery.trim()) {
    return (
      <div className="p-6 text-center text-outline py-20 animate-fadeIn">
        <Music size={48} className="mx-auto mb-4 opacity-30" />
        <p className="text-lg">Search for music and albums</p>
      </div>
    )
  }

  return (
    <div className="p-6 animate-fadeIn">
      {loading && (
        <div className="text-center text-on-surface-variant py-8">
          <LoadingIndicator size="lg" className="mx-auto" />
          <p className="mt-4">Searching...</p>
        </div>
      )}

      {error && (
        <div className="bg-error-container/30 border border-error rounded-lg p-4 mb-6 text-on-error-container text-sm">
          {error}
        </div>
      )}

      {!loading && !error && !hasResults && (
        <div className="text-center text-on-surface-variant py-8">
          <SearchIcon size={48} className="mx-auto mb-4 opacity-50" />
          <p>No results found for "{searchQuery}"</p>
        </div>
      )}

      {!loading && hasResults && (
        <>
          {/* Content type tabs + filter toggle */}
          <div className="flex items-center gap-2 mb-4 overflow-x-auto pb-1">
            {tabs.filter(t => t.count > 0).map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-2 px-4 py-2 rounded-full transition-colors whitespace-nowrap text-sm font-medium ${
                  activeTab === tab.id ? 'bg-primary text-on-surface' : 'text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high'
                }`}
              >
                <tab.icon size={16} />
                {tab.label}
                <span className={`text-xs ${activeTab === tab.id ? 'text-on-surface/70' : 'text-outline'}`}>{tab.count}</span>
              </button>
            ))}
            {showFiltersForTab && (
              <button
                onClick={() => setShowFilters(v => !v)}
                className={`ml-auto shrink-0 flex items-center gap-1.5 px-3 py-2 rounded-full text-sm font-medium transition-colors ${
                  showFilters || hasActiveFilters ? 'bg-secondary-container text-on-secondary-container' : 'text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high'
                }`}
              >
                <SlidersHorizontal size={15} />
                Filters
              </button>
            )}
          </div>

          {/* Filter panel */}
          {showFilters && showFiltersForTab && (
            <div className="mb-5 p-4 bg-surface-container/80 rounded-xl border border-outline-variant animate-fadeIn">
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                <div className="space-y-1">
                  <label className="text-[11px] text-on-surface-variant font-medium uppercase tracking-wide">Duration min</label>
                  <input
                    value={filterDurationMin}
                    onChange={e => setFilterDurationMin(e.target.value)}
                    placeholder="e.g. 3:30"
                    className="w-full px-3 py-2 bg-surface-container-high text-on-surface text-sm rounded-lg focus:outline-none focus:ring-2 focus:ring-primary placeholder:text-outline"
                  />
                </div>
                <div className="space-y-1">
                  <label className="text-[11px] text-on-surface-variant font-medium uppercase tracking-wide">Duration max</label>
                  <input
                    value={filterDurationMax}
                    onChange={e => setFilterDurationMax(e.target.value)}
                    placeholder="e.g. 5:00"
                    className="w-full px-3 py-2 bg-surface-container-high text-on-surface text-sm rounded-lg focus:outline-none focus:ring-2 focus:ring-primary placeholder:text-outline"
                  />
                </div>
                <div className="space-y-1">
                  <label className="text-[11px] text-on-surface-variant font-medium uppercase tracking-wide">Artist</label>
                  <input
                    value={filterArtist}
                    onChange={e => setFilterArtist(e.target.value)}
                    placeholder="e.g. Daft Punk"
                    className="w-full px-3 py-2 bg-surface-container-high text-on-surface text-sm rounded-lg focus:outline-none focus:ring-2 focus:ring-primary placeholder:text-outline"
                  />
                </div>
                <div className="space-y-1">
                  <label className="text-[11px] text-on-surface-variant font-medium uppercase tracking-wide">Album</label>
                  <input
                    value={filterAlbum}
                    onChange={e => setFilterAlbum(e.target.value)}
                    placeholder="e.g. Discovery"
                    className="w-full px-3 py-2 bg-surface-container-high text-on-surface text-sm rounded-lg focus:outline-none focus:ring-2 focus:ring-primary placeholder:text-outline"
                  />
                </div>
              </div>
              {hasActiveFilters && (
                <button onClick={clearFilters} className="mt-3 flex items-center gap-1 text-xs text-on-surface-variant hover:text-on-surface transition-colors">
                  <X size={13} />
                  Clear filters
                </button>
              )}
            </div>
          )}
        </>
      )}

      {/* Songs */}
      {!loading && activeTab === 'songs' && filteredSongs.length > 0 && (
        <div className="space-y-2">
          {filteredSongs.map((song, i) => (
            <div key={song.videoId} className="flex items-center gap-4 p-3 bg-surface-container/50 rounded-xl hover:bg-surface-container transition-colors group animate-slideUp" style={{ animationDelay: `${i * 0.04}s`, animationFillMode: 'backwards' }}>
              <div className="relative">
                <ArtImage src={song.thumbnail} alt="" className="w-12 h-12 rounded object-cover" />
                <span className="absolute bottom-0.5 right-0.5 bg-black/70 text-white text-[10px] px-1 rounded leading-tight">{formatDuration(song.duration)}</span>
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-medium truncate text-on-surface">{song.title}</p>
                <p className="text-sm text-on-surface-variant truncate">
                  <span onClick={e => { e.stopPropagation(); openArtist(song.channelTitle, song.channelId, song.thumbnail) }}
                     className="cursor-pointer hover:text-on-surface">
                    {song.channelTitle}
                  </span>
                  {song.album && <span className="text-outline"> · {song.album}</span>}
                </p>
              </div>
              <div className="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                <button onClick={() => handlePlaySong(song)} className="p-2 bg-primary text-on-surface rounded-full hover:bg-primary/80" title="Play"><Play size={16} /></button>
                <button onClick={() => handleAddToQueue(song)} className="p-2 bg-surface-container-high text-on-surface rounded-full hover:bg-surface-container-highest" title="Queue"><Clock size={16} /></button>
                <button onClick={() => handleAddToPlaylist(song)} className="p-2 bg-surface-container-high text-on-surface rounded-full hover:bg-surface-container-highest" title="Add to playlist"><Plus size={16} /></button>
                <button onClick={() => openArtist(song.channelTitle, song.channelId, song.thumbnail)} className="p-2 bg-surface-container-high text-on-surface rounded-full hover:bg-surface-container-highest" title="Artist"><User size={16} /></button>
              </div>
            </div>
          ))}
          {hasActiveFilters && filteredSongs.length === 0 && (
            <p className="text-center text-on-surface-variant py-6 text-sm">No songs match the current filters</p>
          )}
        </div>
      )}

      {/* Albums */}
      {!loading && activeTab === 'albums' && results.albums.length > 0 && (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
          {results.albums.map((album, i) => (
            <div key={album.playlistId} onClick={() => openAlbum(album)}
                 className="bg-surface-container/50 rounded-xl p-4 cursor-pointer hover:bg-surface-container transition-colors hover:scale-[1.02] animate-scaleIn" style={{ animationDelay: `${i * 0.06}s`, animationFillMode: 'backwards' }}>
              <ArtImage src={album.thumbnail} alt="" className="w-full aspect-square rounded-lg object-cover mb-3" />
              <p className="text-on-surface font-medium truncate">{album.title}</p>
              <p className="text-on-surface-variant text-sm truncate">
                <span onClick={e => { e.stopPropagation(); openArtist(album.channelTitle, album.channelId, album.thumbnail) }}
                   className="cursor-pointer hover:text-on-surface">
                  {album.channelTitle}
                </span>
              </p>
            </div>
          ))}
        </div>
      )}

      {pickerSong && (
        <PlaylistPickerModal song={pickerSong} onClose={() => setPickerSong(null)} />
      )}
    </div>
  );
};
