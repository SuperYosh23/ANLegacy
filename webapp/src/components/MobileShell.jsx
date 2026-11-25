import { useState, useEffect, useCallback } from 'react';
import { Home, Search as SearchIcon, Library as LibraryIcon, Settings, ChevronLeft } from 'lucide-react';
import { useNavigate } from '../context/NavigationContext';
import { usePlayer } from '../context/PlayerContext';
import { Player } from './Player';
import { ExpandedPlayer } from './ExpandedPlayer';
import { Search as SearchComponent } from './Search';
import { Library } from './Library';
import { Stats } from './Stats';
import { MobileSettings } from './MobileSettings';
import { ArtistPage } from './ArtistPage';
import { PlaylistPage } from './PlaylistPage';
import { AlbumPage } from './AlbumPage';
import { LibrarySongsPage } from './LibrarySongsPage';
import { MobileHome } from './MobileHome';

// The phone's layout, matching the native app.
//
// The desktop app is a window: a title bar with a search field, a resizable
// sidebar down the left, and the content beside it. A phone has none of that.
// The native app is a bottom tab bar over full-width content with a mini player
// above it and Now Playing pushed on top, and that is what this reproduces.
//
// The same components are reused, so the two apps stay in step.
const TABS = [
  { id: 'home', label: 'Home', icon: Home },
  { id: 'search', label: 'Search', icon: SearchIcon },
  { id: 'library', label: 'Library', icon: LibraryIcon },
  { id: 'settings', label: 'Settings', icon: Settings },
];

const TITLES = {
  home: 'audioNINJA',
  search: 'Search',
  library: 'Library',
  settings: 'Settings',
  stats: 'Stats',
};

export const MobileShell = () => {
  const [activeTab, setActiveTab] = useState('home');
  const [searchQuery, setSearchQuery] = useState('');
  const { subPage, navigate, navigateBack } = useNavigate();
  const { playerExpanded, setPlayerExpanded, currentSong } = usePlayer();

  const handleTabChange = useCallback((tab) => {
    setActiveTab(tab);
    navigate(null);
    setPlayerExpanded(false);
  }, [navigate, setPlayerExpanded]);

  // A pushed screen takes over the whole view, and the tab bar goes away, the
  // way a navigation push works in the native app.
  const isPushed = !!subPage;

  const renderContent = () => {
    if (subPage?.type === 'artist') return <ArtistPage />;
    if (subPage?.type === 'playlist') return <PlaylistPage />;
    if (subPage?.type === 'album') return <AlbumPage />;
    if (subPage?.type === 'library-songs') return <LibrarySongsPage />;

    switch (activeTab) {
      case 'search': return <SearchComponent searchQuery={searchQuery} setSearchQuery={setSearchQuery} />;
      case 'library': return <Library />;
      case 'stats': return <Stats />;
      case 'settings': return <MobileSettings />;
      case 'home':
      default: return <MobileHome onOpenSearch={() => handleTabChange('search')} />;
    }
  };

  const title = isPushed
    ? (subPage.params?.title || 'Loading')
    : (TITLES[activeTab] || 'audioNINJA');

  return (
    <div className="h-screen bg-surface-dim text-on-surface flex flex-col overflow-hidden">
      {/* Nav bar */}
      <div className="shrink-0 bg-surface-container border-b border-outline-variant flex items-center h-12 px-2">
        {isPushed ? (
          <button
            onClick={navigateBack}
            className="h-10 w-10 flex items-center justify-center rounded-full text-on-surface hover:bg-surface-container-high transition-colors"
            aria-label="Back"
          >
            <ChevronLeft size={22} />
          </button>
        ) : (
          <div className="w-2" />
        )}
        <h1 className="flex-1 text-center text-base font-semibold truncate px-1">{title}</h1>
        <div className="w-10" />
      </div>

      {/* Content */}
      <main className="flex-1 min-h-0 relative overflow-y-auto">
        {renderContent()}
      </main>

      {/* Mini player, above the tab bar, when something is loaded. The Player
          component is a fixed bottom bar, so it is offset up by the tab bar's
          height here. */}
      {!playerExpanded && currentSong && (
        <div className="shrink-0 h-[4.5rem] relative">
          <div className="fixed bottom-[3.75rem] left-0 right-0 z-30">
            <Player playerExpanded={false} />
          </div>
        </div>
      )}

      {/* Tab bar */}
      {!playerExpanded && !isPushed && (
        <nav className="shrink-0 h-[3.75rem] bg-surface-container border-t border-outline-variant flex items-stretch">
          {TABS.map((tab) => {
            const Icon = tab.icon;
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => handleTabChange(tab.id)}
                className={`flex-1 flex flex-col items-center justify-center gap-0.5 transition-colors ${
                  active ? 'text-primary' : 'text-on-surface-variant'
                }`}
                aria-label={tab.label}
              >
                <Icon size={22} />
                <span className="text-[10px] font-medium">{tab.label}</span>
              </button>
            );
          })}
        </nav>
      )}

      {/* Now Playing, full screen, the way the native app pushes it. */}
      {playerExpanded && (
        <div className="fixed inset-0 z-40 bg-surface-dim">
          <ExpandedPlayer />
        </div>
      )}
    </div>
  );
};
