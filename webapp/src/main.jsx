import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
import { PlayerProvider } from './context/PlayerContext'
import { NavigationProvider } from './context/NavigationContext'
import { loadTheme, applyCurrentTheme, applyOledMode } from './utils/colorScheme'
import { seedFromNativeLibrary } from './utils/nativeSeed'

// Initialize theme from saved preferences
//
// The phone passes its chosen theme in the query string, and that wins: the
// native app's theme picker is the one the user actually set, and this app's
// own preference is only a desktop thing.
let requestedTheme = null;
try {
  requestedTheme = new URLSearchParams(window.location.search).get('theme');
} catch {
  // A malformed query string is not worth failing over.
}
try {
  const prefs = JSON.parse(localStorage.getItem('ym_preferences') || '{}');
  document.documentElement.dataset.theme = requestedTheme || prefs.theme || 'dark';
} catch {
  document.documentElement.dataset.theme = requestedTheme || 'dark';
}

// Apply OLED black background if enabled (no-op in light mode)
applyOledMode();

// Apply custom theme if saved
const savedTheme = loadTheme();
if (savedTheme) {
  applyCurrentTheme(savedTheme);
}

// On the phone the library lives in the native app, so it is copied into the
// web app's own storage before the first render. Otherwise the Library and
// Playlists tabs start out empty.
seedFromNativeLibrary().then(() => {
createRoot(document.getElementById('root')).render(
  <StrictMode>
    <NavigationProvider>
      <PlayerProvider>
        <App />
      </PlayerProvider>
    </NavigationProvider>
  </StrictMode>,
)
});
