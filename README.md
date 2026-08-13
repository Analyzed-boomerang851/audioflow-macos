<p align="center">
  <img src="Sources/Shenglan/Resources/ShenglanIcon.png" width="128" height="128" alt="AudioFlow app icon">
</p>

<h1 align="center">AudioFlow</h1>

<p align="center">
  A native macOS menu bar audio mixer for system and per-app sound.
</p>

<p align="center">
  <a href="https://github.com/Pandachan98/audioflow-macos/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Pandachan98/audioflow-macos?style=flat-square"></a>
  <a href="https://github.com/Pandachan98/audioflow-macos/actions/workflows/build.yml"><img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/Pandachan98/audioflow-macos/build.yml?branch=main&style=flat-square&label=build"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-black?style=flat-square"></a>
  <img alt="macOS 14.2 or later" src="https://img.shields.io/badge/macOS-14.2%2B-black?style=flat-square&logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white">
</p>

<p align="center">
  Free, local-first, multilingual, and designed for the Mac.<br>
  A Starry Vibe Coding project.
</p>

## Why AudioFlow?

I wanted a native way to control app audio on macOS, but the tools I found were paid, lacked the localization I needed, or did not fit the visual experience I wanted. So I spent two days vibe-coding AudioFlow: a free and open-source alternative with real Core Audio controls and a native Liquid Glass interface.

This repository is not affiliated with or endorsed by any commercial audio-control product. AudioFlow has its own name, visual identity, implementation, and interaction design.

## Highlights

- **Real system volume control** — reads and changes the active output device volume and mute state through Core Audio.
- **Per-app mixing** — discovers real Core Audio processes and applies independent volume and mute controls.
- **Output routing** — sends an individual app to a selected audio output device.
- **Volume boost** — supports up to 4x per-app gain when extra headroom is needed.
- **Live device discovery** — tracks input, output, Bluetooth, and built-in audio devices.
- **Menu bar control** — a compact controller with configurable icon and volume display styles.
- **App organization** — favorites, media-aware categories, collapsible groups, and drag-to-reorder.
- **Native macOS behavior** — background operation, login launch, window restoration, and full-screen popover support.
- **Liquid Glass interface** — native glass where available, with system-material fallback on earlier macOS versions.
- **Custom appearance** — light, dark, system-following themes, optional background images, opacity, and blur controls.
- **Multilingual UI** — Simplified Chinese, English, Japanese, French, German, and Korean.
- **Local-first privacy** — audio is processed in memory and is never recorded, saved, or uploaded.

## Requirements

- macOS 14.2 or later
- Apple Silicon Mac for the current community build
- System Audio Recording permission for per-app audio control

System master volume and audio-device controls remain available without the audio-recording permission.

## Install

1. Download `AudioFlow.dmg` from the [latest release](https://github.com/Pandachan98/audioflow-macos/releases/latest).
2. Drag **AudioFlow** into **Applications**.
3. Open AudioFlow and grant System Audio Recording permission when prompted.

The downloadable community build is ad-hoc signed and is not Apple-notarized. If macOS blocks the first launch, open **System Settings → Privacy & Security** and choose **Open Anyway**, or build the app from source.

## Build from source

```bash
git clone https://github.com/Pandachan98/audioflow-macos.git
cd audioflow-macos
./build-app.sh
```

The build script creates:

- `dist/AudioFlow.app`
- `dist/AudioFlow-macOS.zip`
- `dist/AudioFlow.dmg`

Public builds use ad-hoc signing by default and never modify your keychain. Maintainers can provide a Developer ID identity explicitly:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-app.sh
```

Useful build options:

```bash
CREATE_DMG=0 ./build-app.sh
INSTALL_AFTER_BUILD=1 ./build-app.sh
INSTALL_AFTER_BUILD=1 OPEN_AFTER_INSTALL=1 ./build-app.sh
```

## How it works

AudioFlow is a SwiftUI and AppKit application backed by Core Audio. It uses process taps, a private aggregate device, and a real-time IOProc pipeline to apply per-process gain without installing a virtual audio driver. Device and process state are refreshed from the operating system rather than a demo data source.

The source tree is intentionally compact:

```text
Sources/
├── Shenglan/                 App lifecycle, UI, localization, and models
└── ShenglanAudioEngine/      Real-time audio processing bridge
PackagingLocalizations/      Localized macOS bundle metadata
InstallerAssets/             DMG presentation assets
```

## Privacy

AudioFlow requests System Audio Recording permission only to identify active audio processes and apply live per-app controls. It does not create recordings, write captured audio to disk, transmit audio, include analytics, or make network requests.

See [Privacy](docs/PRIVACY.md) for the complete policy.

## Contributing

Issues and pull requests are welcome. Please read [Contributing](CONTRIBUTING.md) before submitting a change and use [Security](SECURITY.md) for vulnerability reports.

## License

AudioFlow is released under the [MIT License](LICENSE).

Built by **Starry** as part of a personal Vibe Coding collection.
