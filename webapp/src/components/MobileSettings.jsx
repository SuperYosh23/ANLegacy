import { useState, useEffect, useCallback } from 'react';
import { ChevronRight } from 'lucide-react';

// The phone's Settings, matching the native app's list.
//
// The native app's rows are the ones that matter on a phone, so this is the
// same set in the same order: Playback options, Appearance options, Data
// management, About. Values come from the phone's own preferences over
// /api/settings, so the two apps never disagree about what is set.
//
// Rows that need a native screen - the icon picker, the sleep timer sheet, the
// destructive data actions - show their current value and say where to change
// them, rather than pretending to work.

const Section = ({ title, children }) => (
  <section className="mb-5">
    {title ? (
      <h2 className="text-xs font-semibold uppercase tracking-wide text-on-surface-variant px-4 mb-1.5">
        {title}
      </h2>
    ) : null}
    <div className="bg-surface-container rounded-xl overflow-hidden mx-3">{children}</div>
  </section>
);

const Row = ({ label, value, onClick, children, last }) => (
  <div
    onClick={onClick}
    className={`flex items-center justify-between px-4 py-3 ${last ? '' : 'border-b border-outline-variant'} ${onClick ? 'active:bg-surface-container-high' : ''}`}
  >
    <span className="text-sm text-on-surface">{label}</span>
    {children}
  </div>
);

const Toggle = ({ on, onToggle }) => (
  <button
    onClick={onToggle}
    role="switch"
    aria-checked={on ? 'true' : 'false'}
    className={`w-12 h-6 rounded-full transition-colors shrink-0 ${
      on ? 'bg-primary' : 'bg-surface-container-highest'
    }`}
  >
    <div
      className={`w-5 h-5 bg-white rounded-full transition-all ${
        on ? 'translate-x-6' : 'translate-x-0.5'
      }`}
    />
  </button>
);

const Value = ({ text }) => (
  <span className="text-sm text-on-surface-variant truncate ml-3 max-w-[45%] text-right">
    {text}
  </span>
);

export const MobileSettings = () => {
  const [settings, setSettings] = useState(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await fetch('/api/settings');
      const data = await res.json();
      if (data && data.settings) setSettings(data.settings);
    } catch {
      // Leave the page showing its placeholders rather than an error.
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const set = async (key, value) => {
    setBusy(true);
    try {
      const res = await fetch('/api/settings', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ key, value }),
      });
      const data = await res.json();
      if (data && data.settings) setSettings(data.settings);
    } catch {
      // Leave the current values alone if the write did not land.
    } finally {
      setBusy(false);
    }
  };

  if (!settings) {
    return <div className="p-4 text-sm text-on-surface-variant">Loading settings…</div>;
  }

  // The theme row cycles. The native picker is not reachable from inside the
  // web app, so without this the modern themes would be a one-way door - there
  // would be no way back to the native app at all.
  const nextTheme = (current) => (Number(current) + 1) % 3;

  const hapticLabels = ['Off', 'Light', 'Medium', 'Strong'];
  const haptic = settings.hapticStrength || 0;
  const sleepTimer = settings.sleepTimerActive
    ? `${settings.sleepTimerMinutes} min left`
    : 'Off';

  return (
    <div className="pb-6 pt-1">
      <Section title="Playback options">
        <Row label="Keep Screen Awake">
          <Toggle on={settings.keepAwake} onToggle={() => set('keepAwake', !settings.keepAwake)} />
        </Row>
        <Row label="Show kbps Counter">
          <Toggle on={settings.showKbpsCounter} onToggle={() => set('showKbpsCounter', !settings.showKbpsCounter)} />
        </Row>
        <Row label="Sleep Timer" value={sleepTimer} />
        <Row label="Lyrics Offset">
          <span className="flex items-center gap-2 ml-3">
            <button
              onClick={() => set('lyricsOffset', Math.round((settings.lyricsOffset - 0.5) * 10) / 10)}
              className="w-8 h-8 rounded-full bg-surface-container-highest text-on-surface text-lg leading-none"
            >−</button>
            <span className="text-sm text-on-surface-variant w-12 text-center">
              {settings.lyricsOffset > 0 ? '+' : ''}{Number(settings.lyricsOffset).toFixed(1)}s
            </span>
            <button
              onClick={() => set('lyricsOffset', Math.round((settings.lyricsOffset + 0.5) * 10) / 10)}
              className="w-8 h-8 rounded-full bg-surface-container-highest text-on-surface text-lg leading-none"
            >+</button>
          </span>
        </Row>
        <Row label="Haptic Strength" value={hapticLabels[haptic] || 'Medium'} last
             onClick={() => set('hapticStrength', (haptic + 1) % 4)} />
      </Section>

      <Section title="Appearance options">
        <Row label="Album Art Background">
          <Toggle on={settings.albumArtBackground} onToggle={() => set('albumArtBackground', !settings.albumArtBackground)} />
        </Row>
        <Row label="Enable Animations">
          <Toggle on={settings.animationsEnabled} onToggle={() => set('animationsEnabled', !settings.animationsEnabled)} />
        </Row>
        <Row label="Transition Speed" value={`${Number(settings.transitionSpeed).toFixed(2)}×`} />
        <Row label="iPod Mode">
          <Toggle on={settings.iPodModeEnabled} onToggle={() => set('iPodModeEnabled', !settings.iPodModeEnabled)} />
        </Row>
        <Row label="Recents Tile Size" value={`${Math.round(settings.recentsTileSize)} pt`} />
        {settings.oneHandedSupported ? (
          <Row label="One-Handed Mode" value={settings.oneHandedMode === 0 ? 'Off' : 'On'} />
        ) : null}
        <Row label="App Icon" value={settings.appIconLabel} />
        <Row label="Theme" value={settings.themeName} last
             onClick={() => set('theme', nextTheme(settings.theme))} />
      </Section>

      <Section title="Data management">
        <Row label="Download Queue" value={settings.pendingDownloads ? `${settings.pendingDownloads} waiting` : 'Empty'} />
        <Row label="Offline Downloads" value={`${settings.offlineDownloads} files`} />
        <Row label="Sync with Another Device" />
        <Row label="Refresh Metadata & Artwork" />
        <Row label="Create AN Mini Instance (BETA)" />
        <Row label="Clear Offline Downloads" />
        <Row label="Reset Listening Stats" />
        <Row label="Clear Search History" last />
      </Section>

      <Section title="About">
        <Row label="App" value="audioNINJA" />
        <Row label="Version" value={settings.version} last />
      </Section>

      <p className="px-4 text-xs text-on-surface-variant leading-relaxed">
        Some settings - the sleep timer, the app icon, the data actions - are
        changed in the native app. This list shows their current values.
      </p>
    </div>
  );
};
