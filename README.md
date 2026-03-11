# SwiftGet — Internet Download Manager for macOS

[![Build Status](https://github.com/bhargav59/SwiftGet/actions/workflows/build.yml/badge.svg)](https://github.com/bhargav59/SwiftGet/actions/workflows/build.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-blue?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![Chrome Extension](https://img.shields.io/badge/Chrome-Manifest%20V3-brightgreen?logo=googlechrome)](ChromeExtension/)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)

> **SwiftGet** is a native macOS download manager that replicates and extends the core functionality of Internet Download Manager (IDM) — without requiring Xcode or Apple Developer tooling for end-user installation.

![SwiftGet Screenshot](docs/screenshot.png)

---

## ✨ Key Features

| Feature | Details |
|---|---|
| **Multi-segment Parallel Downloads** | Up to 32 configurable segments — typically 5–8× faster than single-thread |
| **Video Extraction** | 1000+ sites via bundled yt-dlp (YouTube, Vimeo, TikTok, Instagram, Twitter/X…) |
| **Chrome Extension** | Manifest V3 — auto-intercepts downloads, shows floating button on video pages |
| **Resume on Disconnect** | Per-segment byte-range state persisted to disk |
| **Download Scheduler** | Time-window scheduling, bandwidth throttle, auto-shutdown |
| **macOS Integration** | Dock progress, Notification Center, Menu Bar, Share Sheet, Spotlight |
| **No Xcode Required** | Ships as a notarized `.dmg` — double-click to install |
| **Universal Binary** | Apple Silicon (arm64) + Intel (x86_64) |

---

## 🚀 Installation

### From GitHub Releases (recommended)

1. Download `SwiftGet.dmg` from the [latest release](https://github.com/bhargav59/SwiftGet/releases/latest).
2. Open the `.dmg`, drag **SwiftGet** to your **Applications** folder.
3. Launch SwiftGet — no Terminal, no Xcode, no Homebrew required.

### Chrome Extension

1. Install from the [Chrome Web Store](#) (link coming after review).
2. Or load unpacked from the `ChromeExtension/` directory for development.

SwiftGet automatically installs the Native Messaging Host manifest to:

```
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.swiftget.nativehost.json
```

---

## 🏗 Project Structure

```
SwiftGet/
├── SwiftGet/                     # macOS App (Swift / SwiftUI)
│   ├── App/                      # Entry point, AppDelegate, ContentView
│   ├── Engine/                   # DownloadEngine (multi-segment) + VideoExtractor (yt-dlp)
│   ├── Models/                   # DownloadTask, DownloadManager, DownloadCategory
│   ├── Views/                    # SwiftUI views (sidebar, list, detail, add dialog, settings)
│   ├── NativeMessaging/          # swiftget:// URL scheme + NativeMessagingServer
│   ├── Persistence/              # JSON-backed persistence layer
│   ├── Scheduler/                # SchedulerManager (time windows, BW throttle)
│   └── Resources/                # Info.plist, yt-dlp binary
├── ChromeExtension/              # Manifest V3 Chrome Extension
│   ├── manifest.json
│   ├── background.js             # Service worker — download interception, video relay
│   ├── content.js                # XHR/Fetch hooking, floating button, quality picker
│   ├── popup.{html,js,css}       # Extension popup
│   └── options.{html,js}        # Extension settings page
├── NativeMessagingHost/          # Standalone Swift binary (stdin/stdout JSON bridge)
│   └── Sources/NativeMessagingHost/main.swift
├── .github/workflows/
│   ├── build.yml                 # Build, sign, notarize, release
│   └── update-ytdlp.yml          # Weekly yt-dlp auto-update
├── Package.swift                 # Swift Package Manager
└── SwiftGet_PRD.pdf              # Product Requirements Document
```

---

## 🛠 Building from Source

### Prerequisites (CI/developer only)

- macOS 12+ with Xcode 15+
- Swift 5.9+
- Apple Developer account (for signing/notarization)

### Build Native Messaging Host

```bash
swift build --product SwiftGetNativeHost --configuration release --arch arm64 --arch x86_64
```

### Build macOS App (Xcode)

```bash
xcodebuild -scheme SwiftGet -configuration Release archive \
  -archivePath SwiftGet.xcarchive
```

### Package Chrome Extension

```bash
cd ChromeExtension
zip -r ../SwiftGet-ChromeExtension.zip . -x "*.DS_Store"
```

---

## ⚙️ Architecture

### Download Engine

```
DownloadManager (MainActor singleton)
    └── DownloadEngine (actor, per task)
            ├── HEAD probe → file size, Range support, filename, MIME
            ├── Segment builder (1–32 segments via HTTP Range)
            ├── Parallel segment download (async/await + URLSession.bytes)
            ├── Speed sampling & history (live graph)
            └── Assembly → atomic write to destination
```

### Chrome Extension → SwiftGet Bridge

```
Chrome Extension (content.js)
    → detect video streams via XHR/Fetch interception
    → show floating download button + quality picker

Chrome Extension (background.js)
    → intercept chrome.downloads via onCreated
    → relay via swiftget:// URL scheme (primary)
    → fallback: Native Messaging (stdin/stdout JSON)

SwiftGetNativeHost binary
    → reads length-prefixed JSON from stdin
    → invokes `open swiftget://add?url=...`

SwiftGet.app (AppDelegate)
    → handles swiftget:// URL
    → enqueues DownloadTask
```

---

## 🔐 Security & Privacy

- **No outbound telemetry** — zero data sent to SwiftGet servers.
- **All video extraction runs locally** via the bundled `yt-dlp` binary.
- **Optional** anonymous crash reporting (opt-in, clearly disclosed).
- **Notarized** by Apple — passes Gatekeeper on every Mac.
- **ToS acknowledgment** on first launch: users acknowledge responsibility for downloaded content.

---

## 📋 Requirements

- macOS 12 Monterey or later (macOS 10.15 Catalina via compatibility build)
- Google Chrome 88+ for the extension
- ~100 MB disk space (including embedded Python runtime for yt-dlp)

---

## 🗺 Roadmap

| Milestone | Timeline | Highlights |
|---|---|---|
| **Alpha** | Months 1–2 | Core engine, basic UI, manual URL add |
| **Beta** | Month 3 | Chrome extension, top 10 video sites, queue management |
| **v1.0** | Month 4 | 50+ video sites, notarized DMG, Chrome Web Store |
| **v1.1** | Month 6 | Performance tuning, polish |
| **v1.2** | Month 9 | Safari extension, 5-language localization |
| **v2.0** | Month 12 | Torrent support, Firefox/Edge plugins |

---

## 📄 License

SwiftGet is released under the [MIT License](LICENSE).

**Disclaimer:** SwiftGet is a download utility. Responsibility for downloaded content rests with the user. Downloading copyrighted content without authorization may violate platform Terms of Service and applicable law.

---

## 🙏 Acknowledgements

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) — the best video extraction tool available (MIT/Unlicense)
- [Sparkle](https://sparkle-project.org) — macOS auto-update framework
- Apple SwiftUI & Swift Concurrency teams
