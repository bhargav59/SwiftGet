# ⚡ SwiftGet

> **Internet Download Manager for macOS** — with Chrome Extension

SwiftGet is a native macOS download manager that delivers IDM-level performance: multi-segment parallel downloading, broad video platform support, and a polished HIG-compliant UI. It ships as a signed, notarized `.dmg` requiring no Xcode or Terminal for installation.

[![Build Status](https://github.com/bhargav59/SwiftGet/actions/workflows/build.yml/badge.svg)](https://github.com/bhargav59/SwiftGet/actions/workflows/build.yml)
[![macOS](https://img.shields.io/badge/macOS-12%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## ✨ Features

- **Multi-segment parallel downloading** — up to 32 simultaneous connections per file (5–8× faster than browser downloads)
- **Resume interrupted downloads** — persists per-segment byte ranges; auto-resumes after network reconnects
- **Chrome Extension (Manifest V3)** — intercepts qualifying downloads and detects video streams from 50+ platforms
- **Video detection** — captures HLS (`.m3u8`), DASH (`.mpd`), and progressive MP4/WebM streams
- **Download queue management** — priority levels, drag-to-reorder, pause/resume/cancel, batch operations
- **Scheduler** — configure download windows (e.g. off-peak 2–6 AM), per-download scheduled start
- **Bandwidth throttling** — per-download and global speed limits
- **macOS integration** — Dock progress badge, Notification Center alerts, Menu Bar quick-add
- **Universal Binary** — native Apple Silicon (arm64) + Intel (x86_64) support
- **Zero-friction install** — notarized `.dmg`, double-click to install, no Xcode/Terminal required

---

## 📋 Requirements

- macOS 12 Monterey or later
- Google Chrome (for the browser extension)

---

## 🚀 Installation

### macOS App

1. Download `SwiftGet-<version>.dmg` from [Releases](https://github.com/bhargav59/SwiftGet/releases)
2. Open the DMG and drag SwiftGet to Applications
3. Launch SwiftGet from Applications or Spotlight

### Chrome Extension

1. Download `SwiftGet-Chrome-Extension.zip` from [Releases](https://github.com/bhargav59/SwiftGet/releases)
2. Extract the ZIP
3. Open Chrome → `chrome://extensions/` → Enable **Developer mode**
4. Click **Load unpacked** and select the extracted folder

> Once published on the Chrome Web Store, installation will be a single click.

---

## 🏗️ Project Structure

```
SwiftGet/
├── Sources/SwiftGet/
│   ├── SwiftGetApp.swift          # @main entry point
│   ├── AppDelegate.swift          # App lifecycle, URL scheme
│   ├── Models/
│   │   └── DownloadItem.swift     # Data models
│   ├── Engine/
│   │   └── DownloadEngine.swift   # Multi-segment download core
│   ├── Manager/
│   │   └── DownloadManager.swift  # Queue & lifecycle management
│   ├── Scheduler/
│   │   └── DownloadScheduler.swift
│   ├── NativeMessaging/
│   │   └── NativeMessagingBridge.swift  # Chrome ↔ App IPC
│   ├── MenuBar/
│   │   └── MenuBarManager.swift
│   └── Views/
│       ├── MainWindowView.swift   # 3-pane layout
│       └── AddDownloadView.swift
├── ChromeExtension/
│   ├── manifest.json              # MV3 manifest
│   ├── background.js              # Service worker
│   ├── content.js                 # Video stream detection
│   ├── popup.html / popup.js      # Extension popup
│   ├── options.html / options.js  # Settings page
│   └── rules.json                 # Declarative Net Request rules
├── Tests/SwiftGetTests/
│   └── DownloadManagerTests.swift
├── .github/workflows/
│   └── build.yml                  # CI/CD pipeline
├── Package.swift
└── SwiftGet_PRD.pdf
```

---

## 🔧 Building from Source

```bash
# Build (requires Xcode command-line tools)
swift build -c release --arch arm64 --arch x86_64

# Run tests
swift test --parallel

# Create app bundle (see .github/workflows/build.yml for full pipeline)
```

---

## 🌐 Chrome Extension — Supported Platforms

| Category | Platforms |
|---|---|
| Video Hosting | YouTube, Vimeo, Dailymotion, Rumble |
| Social Media | Twitter/X, Instagram, Facebook, TikTok, Reddit, Pinterest |
| Live Streaming | Twitch (VODs), YouTube Live archives |
| News & Media | CNN, BBC, NBC, NYT Video, AP, Reuters |
| Generic | Any direct `.mp4`, `.webm`, `.mov`, `.avi`, `.mkv`, `.m3u8` URL |

---

## ⚙️ Architecture

| Component | Technology |
|---|---|
| UI Framework | SwiftUI + AppKit hybrid |
| Download Engine | Swift Concurrency (`async/await`, `withTaskGroup`) + URLSession |
| Video Extraction | Bundled yt-dlp (planned v1.1) |
| Extension Bridge | Chrome Native Messaging + `swiftget://` URL scheme |
| Data Persistence | Core Data + SQLite |
| Build System | Swift Package Manager + GitHub Actions |
| Distribution | Notarized `.dmg` via GitHub Actions CI/CD |

---

## 🔐 Privacy & Security

- **No telemetry** — zero data transmitted to external servers
- **Local processing only** — all download management and video extraction runs on your Mac
- **Notarized by Apple** — passes macOS Gatekeeper; no security warnings
- Optional anonymous crash reporting (opt-in during onboarding)

---

## 📄 Legal

SwiftGet is a download utility. Users are responsible for compliance with applicable laws and platform Terms of Service when downloading content. SwiftGet does not condone copyright infringement.

---

## 🤝 Contributing

Pull requests are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details.
