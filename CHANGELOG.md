# Changelog

All notable changes to AudioFlow are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-08-14

### Added

- Minimal and Full menu-bar popover styles, switchable from General settings and persisted locally.
- A compact global app order for Minimal mode with drag-to-reorder and restart-safe persistence.
- A dedicated 1.1.0 release note that records the iteration scope and validation evidence.

### Changed

- Reduced the Minimal popover width from 420 pt to 336 pt and app-row height from 48 pt to 44 pt.
- Minimal mode now shows only overall volume, app icons and names, mute controls, volume sliders, percentages, and a 16 pt reorder handle.
- Full mode keeps the existing device selectors, categories, favorites, grouped ordering, output routing, refresh, controller, and quit actions.
- Popover content and preferred size refresh immediately when the selected style changes.

### Verified

- `swift build -Xswiftc -warnings-as-errors`
- Release app bundle build and strict ad-hoc signature verification.
- Settings UI inspection for the two style choices and persisted preference.

## [1.0.0] - 2026-08-13

### Added

- Native macOS menu bar controller and full audio console.
- Real Core Audio master-volume, mute, and device controls.
- Per-app volume, mute, boost, and output routing.
- Live audio-process discovery with favorites, categories, collapsing, and reordering.
- Light, dark, and system-following themes with Liquid Glass support.
- Custom background image, panel opacity, image opacity, and blur controls.
- Login launch, localized menu bar display styles, and permission management.
- Simplified Chinese, English, Japanese, French, German, and Korean interfaces.
- Drag-to-install DMG and ZIP distribution artifacts.

[Unreleased]: https://github.com/starry-sky-chan/audioflow-macos/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/starry-sky-chan/audioflow-macos/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/starry-sky-chan/audioflow-macos/releases/tag/v1.0.0
