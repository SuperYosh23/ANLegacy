import { useState, useEffect, useRef } from 'react';
import { Settings as SettingsIcon, Moon, Sun, Download, Upload, Trash2, Check, Image as ImageIcon, Palette, RotateCcw, ChevronDown, SlidersVertical, Smartphone } from 'lucide-react';
import { storage } from '../utils/storage';
import { extractColorsFromImage, generatePaletteFromSource, applyTheme, loadTheme, applyCurrentTheme, resetTheme, applyOledMode } from '../utils/colorScheme';
import { EQPanel } from './EQPanel';


function CollapsibleSection({ title, icon: Icon, defaultOpen = false, children }) {
  const [open, setOpen] = useState(defaultOpen);
  const [closing, setClosing] = useState(false);

  const toggle = () => {
    if (open) {
      setClosing(true);
      setTimeout(() => { setClosing(false); setOpen(false); }, 150);
    } else {
      setOpen(true);
    }
  };

  return (
    <div className="bg-surface-container/50 rounded-xl">
      <button
        onClick={toggle}
        className="w-full flex items-center justify-between px-6 py-4 overflow-hidden rounded-xl"
      >
          <h3 className="text-lg font-semibold text-on-surface flex items-center gap-2">
          {Icon && <Icon size={20} />}
          {title}
        </h3>
        <ChevronDown size={20} className={`text-on-surface-variant transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>

      {(open || closing) && (
        <div className={`overflow-hidden transition-all duration-150 ease-in-out ${closing ? 'max-h-0 opacity-0' : 'max-h-[2000px] opacity-100'}`}>
          <div className={`px-6 pb-6 ${closing ? 'animate-slideUpOut' : 'animate-slideUp'}`}>
            {children}
          </div>
        </div>
      )}
    </div>
  );
}

export const Settings = () => {
  const [preferences, setPreferences] = useState({ theme: 'dark', autoplay: true });
  const [importStatus, setImportStatus] = useState('');
  const [syncState, setSyncState] = useState({ running: false, message: '' });

  const importRef = useRef(null);

  const [customTheme, setCustomTheme] = useState(() => loadTheme());
  const [extractedColors, setExtractedColors] = useState([]);
  const [sourceColor, setSourceColor] = useState('');
  const imageInputRef = useRef(null);
  const [generatedPreview, setGeneratedPreview] = useState(null);
  const [extracting, setExtracting] = useState(false);

  useEffect(() => {
    setPreferences(storage.getPreferences());
  }, []);

  const handleToggleTheme = () => {
    const newTheme = preferences.theme === 'dark' ? 'light' : 'dark';
    const newPreferences = { ...preferences, theme: newTheme };
    setPreferences(newPreferences);
    storage.savePreferences(newPreferences);
    document.documentElement.dataset.theme = newTheme;
    if (customTheme) applyCurrentTheme(customTheme);
    applyOledMode();
  };

  const handleToggleOledBackground = () => {
    const newPreferences = { ...preferences, oledBackground: !preferences.oledBackground };
    setPreferences(newPreferences);
    storage.savePreferences(newPreferences);
    applyOledMode();
  };

  const handleToggleArtworkBackground = () => {
    const newPreferences = { ...preferences, artworkBackground: !preferences.artworkBackground };
    setPreferences(newPreferences);
    storage.savePreferences(newPreferences);
  };

  const handleToggleAutoplay = () => {
    const newPreferences = { ...preferences, autoplay: !preferences.autoplay };
    setPreferences(newPreferences);
    storage.savePreferences(newPreferences);
  };

  const handleToggleFilterExplicit = () => {
    const newPreferences = { ...preferences, filterExplicit: !preferences.filterExplicit };
    setPreferences(newPreferences);
    storage.savePreferences(newPreferences);
  };

  const DATA_KEYS = ['ym_playlists', 'ym_listening_history', 'ym_preferences', 'ym_eq_settings', 'ym_eq_presets', 'ym_custom_theme', 'ym_sidebar_width'];

  const handleExport = () => {
    const data = { exportedAt: new Date().toISOString() };
    DATA_KEYS.forEach(key => {
      const val = localStorage.getItem(key);
      if (val !== null) data[key] = val;
    });
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `audioninja-data-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleImport = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      try {
        const data = JSON.parse(ev.target.result);
        const keys = DATA_KEYS;
        let count = 0;
        keys.forEach(key => {
          if (data[key] !== undefined) {
            localStorage.setItem(key, data[key]);
            count++;
          }
        });
        setImportStatus(`Imported ${count} data sections. Refreshing...`);
        setTimeout(() => window.location.reload(), 1500);
      } catch {
        setImportStatus('Invalid file. Please select a valid export file.');
        setTimeout(() => setImportStatus(''), 3000);
      }
    };
    reader.readAsText(file);
    e.target.value = '';
  };

  const handleImageUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setExtracting(true);
    try {
      const colors = await extractColorsFromImage(file);
      setExtractedColors(colors);
      if (colors.length > 0) {
        setSourceColor(colors[0]);
        const palette = generatePaletteFromSource(colors[0]);
        setGeneratedPreview(palette);
      }
    } catch (err) {
      console.error('Failed to extract colors:', err);
    } finally {
      setExtracting(false);
    }
    e.target.value = '';
  };

  const handleColorPick = (color) => {
    setSourceColor(color);
    if (color) {
      const palette = generatePaletteFromSource(color);
      setGeneratedPreview(palette);
    } else {
      setGeneratedPreview(null);
    }
  };

  const handleApplyTheme = () => {
    if (!generatedPreview) return;
    applyTheme(generatedPreview);
    setCustomTheme(generatedPreview);
  };

  const handleResetTheme = () => {
    resetTheme();
    setCustomTheme(null);
    setGeneratedPreview(null);
    setSourceColor('');
    setExtractedColors([]);
  };

  const handleMobileSync = async () => {
    if (!window.electronAPI?.syncWithMobile) {
      setSyncState({ running: false, message: 'Mobile sync is only available in the desktop app.' });
      return;
    }
    setSyncState({ running: true, message: 'Looking for an audioNINJA Legacy mobile device on this network...' });
    try {
      const result = await window.electronAPI.syncWithMobile(storage.getPlaylists());
      if (result?.ok) {
        storage.savePlaylists(result.playlists);
        window.dispatchEvent(new Event('playlists-changed'));
        const merged = result.playlists.length;
        setSyncState({ running: false, message: `Sync complete. ${merged} playlist${merged === 1 ? '' : 's'} on this device.` });
      } else {
        setSyncState({ running: false, message: result?.error || 'Sync failed.' });
      }
    } catch (err) {
      console.error('Mobile sync failed:', err);
      setSyncState({ running: false, message: 'Sync failed. See the console for details.' });
    }
  };

  const colorSwatches = [sourceColor, ...extractedColors.filter(c => c !== sourceColor)].filter(Boolean);

  return (
    <div className="p-6 animate-fadeIn">
      <h2 className="text-2xl font-bold text-on-surface mb-6 flex items-center gap-2">
        <SettingsIcon size={24} />
        Settings
      </h2>

      <div className="space-y-4">
        <CollapsibleSection title="Preferences" icon={SettingsIcon}>
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <span className="text-on-surface">Autoplay</span>
              <button
                onClick={handleToggleAutoplay}
                className={`w-12 h-6 rounded-full transition-all ${
                  preferences.autoplay ? 'bg-primary' : 'bg-surface-container-high'
                }`}
              >
                <div
                  className={`w-5 h-5 bg-white rounded-full transition-all ${
                    preferences.autoplay ? 'translate-x-6' : 'translate-x-0.5'
                  }`}
                />
              </button>
            </div>

            <div className="border-t border-outline-variant" />

            <div className="flex items-center justify-between">
              <div>
                <span className="text-on-surface">Filter explicit music</span>
                <p className="text-xs text-on-surface-variant mt-0.5">Hide songs marked as explicit in search and recommendations</p>
              </div>
              <button
                onClick={handleToggleFilterExplicit}
                className={`w-12 h-6 rounded-full transition-all shrink-0 ml-4 ${
                  preferences.filterExplicit ? 'bg-primary' : 'bg-surface-container-high'
                }`}
              >
                <div
                  className={`w-5 h-5 bg-white rounded-full transition-all ${
                    preferences.filterExplicit ? 'translate-x-6' : 'translate-x-0.5'
                  }`}
                />
              </button>
            </div>

          </div>
        </CollapsibleSection>

        <CollapsibleSection title="Appearance" icon={Palette}>
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                {preferences.theme === 'dark' ? <Moon size={20} /> : <Sun size={20} />}
                <span className="text-on-surface">Theme</span>
              </div>
              <button
                onClick={handleToggleTheme}
                className="px-4 py-2 bg-surface-container-high text-on-surface rounded-lg hover:bg-surface-container-highest transition-all hover:scale-105 active:scale-95"
              >
                {preferences.theme === 'dark' ? 'Dark' : 'Light'}
              </button>
            </div>

            <div className="border-t border-outline-variant" />

            <div className="flex items-center justify-between">
              <div>
                <span className="text-on-surface">Artwork background</span>
                <p className="text-xs text-on-surface-variant mt-0.5">Blur the now-playing artwork behind the player and queue</p>
              </div>
              <button
                onClick={handleToggleArtworkBackground}
                className={`w-12 h-6 rounded-full transition-all shrink-0 ml-4 ${
                  preferences.artworkBackground ? 'bg-primary' : 'bg-surface-container-high'
                }`}
              >
                <div
                  className={`w-5 h-5 bg-white rounded-full transition-all ${
                    preferences.artworkBackground ? 'translate-x-6' : 'translate-x-0.5'
                  }`}
                />
              </button>
            </div>

            <div className="border-t border-outline-variant" />

            <div className="flex items-center justify-between">
              <div>
                <span className="text-on-surface">OLED black background</span>
                <p className="text-xs text-on-surface-variant mt-0.5">Use a pure black background in dark mode, regardless of theme</p>
              </div>
              <button
                onClick={handleToggleOledBackground}
                className={`w-12 h-6 rounded-full transition-all shrink-0 ml-4 ${
                  preferences.oledBackground ? 'bg-primary' : 'bg-surface-container-high'
                }`}
              >
                <div
                  className={`w-5 h-5 bg-white rounded-full transition-all ${
                    preferences.oledBackground ? 'translate-x-6' : 'translate-x-0.5'
                  }`}
                />
              </button>
            </div>

            <div className="border-t border-outline-variant" />

            {customTheme && (
              <div className="flex items-center gap-2 bg-primary/10 text-primary px-3 py-2 rounded-lg text-sm">
                <Check size={16} />
                Custom theme is active
              </div>
            )}

            <div>
              <p className="text-sm text-on-surface-variant mb-2">Upload an image to extract colors</p>
              <button
                onClick={() => imageInputRef.current?.click()}
                className="flex items-center gap-2 px-4 py-2 bg-surface-container-high text-on-surface rounded-lg hover:bg-surface-container-highest transition-colors"
              >
                <ImageIcon size={18} />
                {extracting ? 'Extracting colors...' : 'Choose Image'}
              </button>
              <input
                ref={imageInputRef}
                type="file"
                accept="image/*"
                className="hidden"
                onChange={handleImageUpload}
              />
            </div>

            {colorSwatches.length > 0 && (
              <div>
                <p className="text-sm text-on-surface-variant mb-2">Choose a color</p>
                <div className="flex flex-wrap gap-2">
                  {colorSwatches.map((color, i) => (
                    <button
                      key={i}
                      onClick={() => handleColorPick(color)}
                      className={`w-8 h-8 rounded-full border-2 transition-all ${
                        sourceColor === color ? 'border-on-surface scale-110' : 'border-transparent'
                      }`}
                      style={{ backgroundColor: color }}
                      title={color}
                    />
                  ))}
                </div>
              </div>
            )}

            <div>
              <p className="text-sm text-on-surface-variant mb-2">Or pick a custom color</p>
              <div className="flex items-center gap-3">
                <input
                  type="color"
                  value={sourceColor || '#FF8A9B'}
                  onChange={(e) => handleColorPick(e.target.value)}
                  className="w-10 h-10 rounded cursor-pointer border-none bg-transparent"
                />
                <span className="text-sm text-on-surface font-mono">{sourceColor || '#FF8A9B'}</span>
              </div>
            </div>

            {generatedPreview && (
              <div>
                <p className="text-sm text-on-surface-variant mb-2">Generated palette</p>
                <div className="space-y-2">
                  {[
                    { label: 'Primary', key: 'primary' },
                    { label: 'On Primary', key: 'on-primary' },
                    { label: 'Primary Container', key: 'primary-container' },
                    { label: 'Secondary', key: 'secondary' },
                    { label: 'Secondary Container', key: 'secondary-container' },
                    { label: 'Tertiary', key: 'tertiary' },
                    { label: 'Tertiary Container', key: 'tertiary-container' },
                    { label: 'Surface', key: 'surface' },
                    { label: 'Surface Container', key: 'surface-container' },
                    { label: 'Surface Container High', key: 'surface-container-high' },
                  ].map(({ label, key }) => {
                    const color = generatedPreview.dark[key];
                    return (
                      <div key={key} className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-lg shrink-0" style={{ backgroundColor: color }} />
                        <span className="text-sm text-on-surface flex-1">{label}</span>
                        <span className="text-xs text-on-surface-variant font-mono">{color}</span>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}

            <div className="flex gap-3 pt-2">
              <button
                onClick={handleApplyTheme}
                disabled={!generatedPreview}
                className="flex items-center gap-2 px-4 py-2 bg-primary text-on-surface rounded-lg hover:bg-primary/80 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <Check size={18} />
                Apply Theme
              </button>
              <button
                onClick={handleResetTheme}
                disabled={!customTheme}
                className="flex items-center gap-2 px-4 py-2 bg-surface-container-high text-on-surface rounded-lg hover:bg-surface-container-highest transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                <RotateCcw size={18} />
                Reset to Default
              </button>
            </div>
          </div>
        </CollapsibleSection>

        <CollapsibleSection title="Equalizer" icon={SlidersVertical}>
          <EQPanel />
        </CollapsibleSection>

<CollapsibleSection title="Sync with Mobile" icon={Smartphone}>
          <p className="text-on-surface-variant text-sm mb-4">
            Sync your playlists with the audioNINJA Legacy app on your mobile device. On the device, open Settings &gt; Sync and choose "Sync with Another Device" within 90 seconds of starting here. Both devices must be on the same Wi-Fi network.
          </p>
          <button
            onClick={handleMobileSync}
            disabled={syncState.running}
            className="flex items-center gap-2 px-4 py-2 bg-primary text-on-surface rounded-lg hover:bg-primary/80 transition-all hover:scale-105 active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Smartphone size={18} />
            {syncState.running ? 'Syncing...' : 'Sync with Mobile'}
          </button>
          {syncState.message && (
            <div className={`mt-3 flex items-start gap-2 text-sm animate-slideUp ${syncState.message.startsWith('Sync complete') ? 'text-primary' : 'text-on-surface-variant'}`}>
              {syncState.message.startsWith('Sync complete') ? <Check size={16} className="mt-0.5 shrink-0" /> : null}
              <span>{syncState.message}</span>
            </div>
          )}
        </CollapsibleSection>

        <CollapsibleSection title="Data Management" icon={Download}>
          <p className="text-on-surface-variant text-sm mb-4">
            All your data (playlists, listening history) is stored locally on your PC. In case you get a new PC or want to reinstall audioNINJA, the buttons below can help you import and export your data.
          </p>
          <div className="flex flex-wrap gap-3">
            <button
              onClick={handleExport}
              className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-on-surface rounded-lg hover:bg-blue-700 transition-all hover:scale-105 active:scale-95"
            >
              <Download size={18} />
              Export Data
            </button>
            <button
              onClick={() => importRef.current?.click()}
              className="flex items-center gap-2 px-4 py-2 bg-teal-600 text-white rounded-lg hover:bg-teal-700 transition-all hover:scale-105 active:scale-95"
            >
              <Upload size={18} />
              Import Data
            </button>
            <button
              onClick={() => {
                if (window.confirm('Are you sure you want to clear all data? This cannot be undone.')) {
                  localStorage.clear();
                  window.location.reload();
                }
              }}
              className="flex items-center gap-2 px-4 py-2 bg-red-700 text-white rounded-lg hover:bg-red-800 transition-all hover:scale-105 active:scale-95"
            >
              <Trash2 size={18} />
              Clear All Data
            </button>
          </div>
          <input
            ref={importRef}
            type="file"
            accept=".json"
            className="hidden"
            onChange={handleImport}
          />
          {importStatus && (
            <div className={`mt-3 flex items-center gap-2 text-sm animate-slideUp ${importStatus.includes('Refreshing') ? 'text-primary' : 'text-primary'}`}>
              <Check size={16} />
              {importStatus}
            </div>
          )}
        </CollapsibleSection>


      </div>
    </div>
  );
};
