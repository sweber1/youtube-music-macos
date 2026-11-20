# YouTube Music for macOS

A lightweight native macOS wrapper for YouTube Music with system integration.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Native macOS app** — No Electron, just a lean WebKit wrapper
- **Media key support** — Control playback with your keyboard's play/pause, next, and previous keys
- **Now Playing integration** — See track info in Control Center with album artwork
- **Frameless design** — Clean, minimal window that blends with YouTube Music's UI
- **Native scrollbars** — macOS-style scrollbars for a consistent look

## Screenshots

![App](screenshots/youtube-app.png)

![Control Center](screenshots/control-center.png)

## Build from source

1. Clone this fork and open `youtube-music-player.xcodeproj` in Xcode.
2. Select **My Mac** and build and run with ⌘R. For local development, select **Sign to Run Locally** in Signing & Capabilities if Xcode asks for a team.

## Account and privacy

- The app runs in the macOS App Sandbox. Its main window only loads YouTube Music, Google sign-in and consent pages, and the YouTube sign-in callback over HTTPS.
- WebKit keeps its own site data for this app. If Google refuses sign-in in WebKit, choose **File → Open YouTube Music in Browser** and use your browser session there.
- The app reads track metadata for macOS Now Playing and fetches artwork from Google and YouTube image hosts without cookies. The fork omits Discord Rich Presence.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 26.1 or later (for building)

## License

MIT
