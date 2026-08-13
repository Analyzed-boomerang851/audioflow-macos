# AudioFlow 1.1.0

Release date: 2026-08-14

This iteration makes the menu-bar popover faster to scan and much less intrusive while preserving the original controller for deeper audio workflows.

## What changed

- Added **Minimal** and **Full** popover styles under **Settings → General → Menu Bar**.
- Set Minimal as the default for new preferences; the chosen style is saved locally across restarts.
- Reduced Minimal mode from 420 pt to 336 pt wide and reduced app rows from 48 pt to 44 pt.
- Kept only overall volume and per-app icon, name, mute, slider, and percentage controls in Minimal mode.
- Added a narrow 16 pt drag handle to every Minimal app row.
- Added a dedicated, persistent global order for Minimal mode so dragging an app changes the real list order and survives restart.
- Kept output/input selection, categories, favorites, grouped ordering, output routing, refresh, controller, and quit actions in Full mode.
- Made the native popover recompute its content and preferred size immediately after a style switch.

## Why

The original popover exposed useful advanced controls but occupied too much screen space for frequent volume changes. The two-style design keeps quick adjustment compact without removing advanced functionality.

## Validation

- Debug build completed with compiler warnings treated as errors.
- Release app bundle built successfully.
- The generated app bundle passed strict deep code-signature verification with the community ad-hoc signature.
- The settings screen was inspected in the built app and exposed both style choices with the Minimal-mode reordering description.

## Compatibility

- macOS 14.2 or later.
- Apple Silicon community build.
- Existing 1.0.0 settings continue to load; the new popover style and Minimal ordering use separate preference keys.
