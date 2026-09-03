# ANLegacy

**audioNINJA Legacy** — a YouTube Music client for legacy iOS devices.

A native, jailbreak-only YouTube Music app for old devices running iOS 6.0+ (armv7), built with
[Theos](https://theos.dev). It talks to YouTube's unofficial InnerTube API to search, browse, and
stream music without needing a modern OS.

## Features

- Search with Songs / Videos / Albums / Artists tabs (cached search history)
- Browse albums, playlists, and artist pages
- Streaming playback via `AVAudioPlayer` with configurable quality (Low / Medium / High)
- Download tracks for offline playback
- Local playlists (create, rename, delete, add tracks via an in-app picker)
- Recently played history and per-track listening stats (most-played, top artists, total time)
- Dedicated **Now Playing** tab with full artwork, seek bar, repeat, and shuffle
- Blurred album-art background behind the player (toggleable)
- Smooth cross-fade tab transitions with a fixed tab bar, animatable / disable-able and
  speed-adjustable; the Now Playing tab icon lights up blue during playback
- Queue view, song context menus, Shuffle All / Play All
- **Peer-to-peer sync:** sync your full library (playlists, library, recents, stats) directly
  between two phones over Wi-Fi via Bonjour, with no desktop or LAN server
- Tab icons rendered from a bundled Font Awesome font

## Requirements

- [Theos](https://theos.dev) on a macOS/Linux host
- A jailbroken iPhone (armv7, iOS 6.0 or newer)
- iOS 6.0 deployment target (set in the `Makefile`)
- [TLSFix](https://github.com/nfzerox/TLSFix) installed and enabled for **AN Legacy** (legacy iOS
  versions ship outdated TLS that fails against modern HTTPS endpoints)

## Building

```sh
THEOS=/path/to/theos make package
```

To build and install directly to a device over SSH:

```sh
THEOS=/path/to/theos THEOS_DEVICE_IP=<ip> make package install
```

The resulting package installs as `com.legacymusic.app` (display name **AN Legacy**).

## Syncing between two phones

In **Settings → Sync**, press **Sync with Another Phone** on *both* phones. Each phone publishes and
discovers the other over Bonjour on the same Wi-Fi network and they exchange their full library
directly — no desktop or LAN server involved. Both phones must run the same app version; if the
versions differ, the sync is refused.

## Settings

- **Playback options** — Keep Screen Awake, Show kbps Counter
- **Appearance options** — Album Art Background, Enable Animations, Transition Speed, Recents Tile
  Size
- **Data management** — Offline Downloads, Sync with Another Phone, Refresh Metadata & Artwork,
  Create AN Mini Instance, Clear Offline Downloads

## Project structure

- `*.m` / `*.h` — app source
- `Resources/` — bundled assets (icons, Info.plist, Font Awesome font)
- `Makefile` — Theos build configuration
- `control` — package metadata for the deb

## License

This project is licensed under the **GNU General Public License v3.0 or later**. See
[LICENSE](LICENSE) for the full text.

## Disclaimer

This project uses unofficial Google/YouTube APIs and is provided as-is. See
[DISCLAIMER.md](DISCLAIMER.md) for the full disclaimer, including the notice that the code was
AI-generated.
