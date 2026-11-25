import { useState } from 'react';
import { Disc3, Search as SearchIcon } from 'lucide-react';
import { useNavigate } from '../context/NavigationContext';
import { youtubeScraperService } from '../services/youtubeScraper';
import { LoadingIndicator } from './LoadingIndicator';
import { ArtImage } from './ArtImage';

export const Albums = () => {
  const [query, setQuery] = useState('');
  const [albums, setAlbums] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [searched, setSearched] = useState(false);
  const { navigate } = useNavigate();

  const handleSearch = async (e) => {
    e.preventDefault();
    if (!query.trim()) return;
    setLoading(true);
    setSearched(true);
    setError('');
    try {
      const results = await youtubeScraperService.searchAlbums(query, 20);
      setAlbums(results);
    } catch (err) {
      console.error('Album search failed:', err);
      setError('Could not reach the music backend. Make sure the Python server is running on port 3614.');
    } finally {
      setLoading(false);
    }
  };

  const handleOpenAlbum = (album) => {
    navigate({ type: 'album', params: album });
  };

  return (
    <div className="p-6">
      <h2 className="text-2xl font-bold text-on-surface mb-6 flex items-center gap-2">
        <Disc3 size={24} />
        Albums
      </h2>

      <form onSubmit={handleSearch} className="mb-6">
        <div className="relative max-w-2xl mx-auto">
          <SearchIcon className="absolute left-4 top-1/2 -translate-y-1/2 text-on-surface-variant" size={20} />
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search for albums..."
            className="w-full pl-12 pr-4 py-3 bg-surface-container text-on-surface rounded-full focus:outline-none focus:ring-2 focus:ring-primary"
          />
          <button
            type="submit"
            className="absolute right-2 top-1/2 -translate-y-1/2 px-6 py-2 bg-primary text-on-surface rounded-full hover:bg-primary/80 transition-colors"
          >
            Search
          </button>
        </div>
      </form>

      {error && (
        <div className="bg-error-container/30 border border-error rounded-lg p-4 mb-6 text-on-error-container text-sm">
          {error}
        </div>
      )}

      {loading && (
        <div className="text-center text-on-surface-variant py-8">
          <LoadingIndicator size="lg" className="mx-auto" />
          <p className="mt-4">Searching albums...</p>
        </div>
      )}

      {!loading && !error && searched && albums.length === 0 && (
        <div className="text-center text-on-surface-variant py-8">
          <Disc3 size={48} className="mx-auto mb-4 opacity-50" />
          <p>No albums found for "{query}"</p>
        </div>
      )}

      {!loading && albums.length > 0 && (
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
          {albums.map((album) => (
            <div
              key={album.playlistId}
              onClick={() => handleOpenAlbum(album)}
              className="bg-surface-container/50 rounded-xl p-4 cursor-pointer hover:bg-surface-container transition-colors hover:scale-[1.02]"
            >
              <ArtImage
                src={album.thumbnail}
                alt={album.title}
                className="w-full aspect-square rounded-lg object-cover mb-3"
              />
              <p className="text-on-surface font-medium truncate">{album.title}</p>
              <p className="text-on-surface-variant text-sm truncate">
                {album.channelTitle}
              </p>
              <p className="text-outline text-xs mt-1">{album.videoCount} tracks</p>
            </div>
          ))}
        </div>
      )}

      {!searched && !loading && (
        <div className="text-center text-on-surface-variant py-12">
          <Disc3 size={64} className="mx-auto mb-4 opacity-30" />
          <p className="text-lg">Search for an artist or album name to find albums</p>
        </div>
      )}
    </div>
  );
};
