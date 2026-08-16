# ANLegacy

**audioNINJA Legacy** — a YouTube Music client for legacy iOS devices.

A native, jailbreak-only YouTube Music app for old devices running iOS 6.0+ (armv7), built with
[Theos](https://theos.dev). It talks to YouTube's unofficial InnerTube API to search, browse, and
stream music without needing a modern OS.

## Features

- Search for songs, albums, and artists
- Trending chart fetched straight from YouTube Music's charts page
- Browse albums, playlists, and artist pages
- Streaming playback via `AVAudioPlayer` with configurable quality (Low / Medium / High)
- Download tracks for offline playback
- Local playlists (create, rename, delete, add tracks)
- Recently played history
- Now Playing screen with full artwork, seek bar, repeat, and shuffle
- Mini now-playing bar above the tab bar
- Queue view
- Tab icons rendered from a bundled Font Awesome font

## Requirements

- [Theos](https://theos.dev) on a macOS/Linux host
- A jailbroken iPhone (armv7, iOS 6.0 or newer)
- iOS 6.0 deployment target (set in the `Makefile`)
- [TLSFix](https://github.com/nfzerox/TLSFix) installed and enabled for **AN Legacy** (legacy iOS versions ship outdated TLS that fails against modern HTTPS endpoints)

## Building

```sh
THEOS=/path/to/theos make package
```

To build and install directly to a device over SSH:

```sh
THEOS=/path/to/theos THEOS_DEVICE_IP=<ip> make package install
```

The resulting package installs as `com.legacymusic.app` (display name **AN Legacy**).

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
