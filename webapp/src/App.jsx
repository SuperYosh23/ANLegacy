import { useState, useRef, useEffect, useCallback } from 'react';
import { Search as SearchIcon, Play, Minus, Square, X } from 'lucide-react';
import { useNavigate } from './context/NavigationContext';
import { usePlayer } from './context/PlayerContext';
import { Sidebar } from './components/Sidebar';
import { Search as SearchComponent } from './components/Search';
import { Recommendations } from './components/Recommendations';
import { Library } from './components/Library';
import { Stats } from './components/Stats';
import { LibrarySongsPage } from './components/LibrarySongsPage';
import { Settings as SettingsComponent } from './components/Settings';
import { Player } from './components/Player';
import { ExpandedPlayer } from './components/ExpandedPlayer';
import { ArtistPage } from './components/ArtistPage';
import { PlaylistPage } from './components/PlaylistPage';
import { AlbumPage } from './components/AlbumPage';
import { initGlobalRipple } from './utils/rippleEffect';
import { storage } from './utils/storage';
import { MobileShell } from './components/MobileShell';

const EXPANDED_W = 224;
const COLLAPSED_W = 64;
const THRESHOLD = 120;

// The phone runs the app in its own layout, with a bottom tab bar instead of
// a sidebar. The native app sets this flag when it serves the bundle, so the
// same code serves both the desktop window and the phone.
export const isMobileLayout = () => {
  if (typeof window === 'undefined') return false;
  if (window.__AN_MOBILE) return true;
  // The phone asks for the phone layout with ?mobile=1. A script cannot be
  // used for this: the page's own scripts run before anything injected after
  // loadRequest: would reach them.
  try {
    if (new URLSearchParams(window.location.search).get('mobile') === '1') return true;
  } catch {
    // A malformed query string is not worth failing over.
  }
  // A narrow viewport also means a phone, in case the parameter is ever missed.
  return window.innerWidth < 640;
};

function App() {
  const [activeTab, setActiveTab] = useState('home');
  const [searchQuery, setSearchQuery] = useState('');
  const [keepExpanded, setKeepExpanded] = useState(false);
  const [sidebarWidth, setSidebarWidth] = useState(() => storage.getSidebarWidth() ?? EXPANDED_W);
  const [dragging, setDragging] = useState(false);
  const [winMaximized, setWinMaximized] = useState(false);
  const searchRef = useRef(null);
  const { subPage, navigate } = useNavigate();
  const { playerExpanded, setPlayerExpanded, dragOffset } = usePlayer();
  const collapsed = sidebarWidth < THRESHOLD;

  useEffect(() => {
    storage.saveSidebarWidth(sidebarWidth);
  }, [sidebarWidth]);

  useEffect(() => {
    initGlobalRipple();
  }, []);

  useEffect(() => {
    if (!window.electronAPI?.isElectron) return;
    window.electronAPI.isMaximized().then(setWinMaximized);
    window.electronAPI.onMaximizeChange(setWinMaximized);
  }, []);

  const handleWinMinimize = () => window.electronAPI?.minimize();
  const handleWinMaximize = () => window.electronAPI?.maximize();
  const handleWinClose = () => window.electronAPI?.close();

  const handleMinimize = () => {
    document.body.style.overflow = '';
    setKeepExpanded(true);
    setPlayerExpanded(false);
    setTimeout(() => setKeepExpanded(false), 350);
  };

  useEffect(() => {
    if (activeTab === 'search' && searchRef.current) {
      searchRef.current.focus();
    }
  }, [activeTab]);

  const playerExpandedRef = useRef(playerExpanded);
  playerExpandedRef.current = playerExpanded;
  useEffect(() => {
    if (playerExpandedRef.current) setPlayerExpanded(false);
  }, [activeTab, subPage, setPlayerExpanded]);

  useEffect(() => {
    if (playerExpanded || keepExpanded) {
      document.body.style.overflow = 'hidden';
    }
    return () => { document.body.style.overflow = ''; };
  }, [playerExpanded, keepExpanded]);

  const handleSearch = (e) => {
    e.preventDefault();
    if (!searchQuery.trim()) return;
    setActiveTab('search');
    navigate(null);
  };

  const handleTabChange = (tab) => {
    setActiveTab(tab);
    navigate(null);
    setPlayerExpanded(false);
  };

  const handleDragStart = useCallback((e) => {
    e.preventDefault();
    setDragging(true);
    const startX = e.clientX;
    const startW = sidebarWidth;

    const onMove = (ev) => {
      const delta = ev.clientX - startX;
      const newW = Math.min(360, Math.max(COLLAPSED_W, startW + delta));
      setSidebarWidth(newW);
    };

    const onUp = () => {
      document.removeEventListener('pointermove', onMove);
      document.removeEventListener('pointerup', onUp);
      setDragging(false);
      setSidebarWidth(w => w < THRESHOLD ? COLLAPSED_W : w);
    };

    document.addEventListener('pointermove', onMove);
    document.addEventListener('pointerup', onUp);
  }, [sidebarWidth]);

  const renderMain = () => {
    if (subPage?.type === 'artist') return <ArtistPage />;
    if (subPage?.type === 'playlist') return <PlaylistPage />;
    if (subPage?.type === 'album') return <AlbumPage />;
    if (subPage?.type === 'library-songs') return <LibrarySongsPage />;

    switch (activeTab) {
      case 'home': return <Recommendations />;
      case 'library': return <Library />;
      case 'search': return <SearchComponent searchQuery={searchQuery} setSearchQuery={setSearchQuery} />;
      case 'stats': return <Stats />;
      case 'settings': return <SettingsComponent />;
      default: return <Recommendations />;
    }
  };

  return (
    <div className={`h-screen bg-surface-dim text-on-surface flex flex-col ${playerExpanded ? 'overflow-hidden' : ''}`}>
      {isMobileLayout() ? <MobileShell /> : <>
      {/* Top bar */}
      <div data-oled-chrome className="relative z-40 bg-surface-container border-b border-outline-variant flex items-center shrink-0 select-none h-12" style={{ WebkitAppRegion: 'drag' }}>
        <div className="flex items-center gap-2 px-3 shrink-0" style={{ WebkitAppRegion: 'no-drag' }}>
          <Play size={18} className="text-primary" />
          <span className="text-sm font-bold" style={{ fontFamily: "system-ui, 'Segoe UI', Roboto, sans-serif" }}>audio<span className="text-primary">NINJA</span></span>
        </div>
        <div className="flex-1 flex justify-center px-4">
          <form onSubmit={handleSearch} className="relative w-full max-w-xl" style={{ WebkitAppRegion: 'no-drag' }}>
            <SearchIcon className="absolute left-3 top-1/2 -translate-y-1/2 text-outline" size={18} />
            <input
              ref={searchRef}
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder='Search for songs, albums...'
              className="w-full pl-10 pr-4 py-2 bg-surface text-on-surface text-sm rounded-full focus:outline-none focus:ring-2 focus:ring-primary shadow-sm"
            />
          </form>
        </div>
        {window.electronAPI?.isElectron && (
          <div className="flex h-full shrink-0" style={{ WebkitAppRegion: 'no-drag' }}>
            <button onClick={handleWinMinimize} className="px-3 h-full text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high transition-colors" title="Minimize">
              <Minus size={14} />
            </button>
            <button onClick={handleWinMaximize} className="px-3 h-full text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high transition-colors" title={winMaximized ? 'Restore' : 'Maximize'}>
              <Square size={12} />
            </button>
            <button onClick={handleWinClose} className="px-3 h-full text-on-surface-variant hover:text-white hover:bg-red-600 transition-colors" title="Close">
              <X size={14} />
            </button>
          </div>
        )}
      </div>

      {/* Sidebar + Main content */}
      <div className="flex flex-1 min-h-0 relative">
        <div className="relative shrink-0 h-full" style={{ width: sidebarWidth }}>
          <Sidebar activeTab={activeTab} onTabChange={handleTabChange} onNavigate={() => setPlayerExpanded(false)} collapsed={collapsed} dragging={dragging} width={sidebarWidth} />
          {/* Drag handle */}
          <div
            onPointerDown={handleDragStart}
            className={`absolute top-0 right-0 w-1.5 h-full cursor-col-resize z-50 transition-colors ${dragging ? 'bg-primary/40' : 'hover:bg-primary/30'}`}
          />
        </div>
        <main className="flex-1 relative" style={{ overflow: (playerExpanded || keepExpanded) ? 'hidden' : 'auto', paddingBottom: (playerExpanded || keepExpanded) ? 0 : '6rem' }}>
          <div>
            {renderMain()}
          </div>
        </main>
      </div>

      {(playerExpanded || keepExpanded || dragOffset > 0) && (
        <div className="fixed z-30" style={{ top: '3rem', left: sidebarWidth, right: 0, bottom: 0 }}>
          <ExpandedPlayer closing={!playerExpanded && keepExpanded} onMinimize={handleMinimize} />
        </div>
      )}

      <Player playerExpanded={playerExpanded} />
      </>}
    </div>
  );
}

export default App;
