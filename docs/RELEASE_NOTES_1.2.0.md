# AudioFlow 1.2.0

Release date: 2026-08-14

AudioFlow 1.2.0 turns the Mixer into a real sound-shaping workspace while keeping everyday volume control compact. This release adds live total and per-app equalization, stronger tone and acoustic-space presets, reliable preset memory, and a broad pass over runtime and animation performance.

## What changed

### Real total and per-app EQ

- Added a real-time ten-band graphic equalizer at both total-output and per-app stages.
- Added preamp headroom, soft peak protection, and real stereo balance without adding gain to either channel.
- Made total and per-app EQ mutually exclusive: enabling one scope automatically disables the other.
- Added a conditional **Turn Off All EQ** action to the Mixer and menu-bar popover. It appears whenever Total EQ is enabled, or when an EQ belonging to a currently listed app is enabled; remembered EQ state from an exited app does not expose the action.
- Turning off all EQ stages retains every preset value for later use.

### Presets, rooms, and persistence

- Added stronger tone presets for passthrough, HiFi clarity, vocal clarity, bass boost, pop, rock, and custom curves.
- Added real-time room processing with Small Room, Studio, Home Theater, Theater, Concert Hall, and Cathedral scenes.
- Added adjustable room intensity, room size, damping, pre-delay, and stereo width.
- Each total or app preset now remembers its own bands, preamp, room settings, and stereo balance.
- Reset restores only the selected preset to its factory profile without erasing other remembered presets.

### Interface and localization

- Reworked tone and space presets into two clear galleries and kept the full set visible.
- Replaced the response polyline with a smooth animated curve and increased visual amplitude without changing DSP values.
- Moved live DSP status into the upper-right header and removed the redundant signal-chain footer.
- Replaced ambiguous power-only EQ actions with a literal slashed-EQ symbol and localized text.
- Added complete EQ interface and feedback copy for Simplified Chinese, English, Japanese, French, German, and Korean.
- Hid scroll indicators throughout the controller, device, settings, application-list, and menu-bar views while retaining scrolling.
- Kept the Mixer shutdown action on one line at supported window widths.

### Runtime and motion performance

- Moved periodic Core Audio device, volume, mute, topology, latency, capability, and login-item reads off the main thread.
- Coalesced overlapping refresh work and cached device and process metadata used by recurring scans.
- Removed synchronous Core Audio reads from SwiftUI device rendering and made device writes optimistic and asynchronous.
- Unified navigation, popover, button, disclosure, preset, and reorder motion around a shared timing system.
- Stopped animating entire glass workspaces during page changes and removed stacked EQ spring animations.
- Replaced the remaining SwiftUI EQ sliders with the native throttled slider bridge and capped visible ten-band drag publication at 60 Hz while preserving exact final values.

## Behavior and compatibility

- Existing 1.1.0 preferences continue to load.
- If older preferences contain both total and app EQ enabled, the migration keeps the visible total-EQ choice and disables app EQ stages.
- Audio remains processed locally in memory and is never recorded, saved, or uploaded.
- macOS 14.2 or later; Apple Silicon community build.
- The community package is ad-hoc signed and is not Apple-notarized.

## Validation

- Debug tests passed with compiler warnings treated as errors.
- Six Swift tests cover preset memory, selected-preset reset, legacy decoding, non-destructive global EQ shutdown, conditional shutdown visibility, and localization.
- Release app, ZIP, and DMG were rebuilt from the 1.2.0 source and passed strict deep code-signature verification.
- Installed-app inspection covered Mixer, Devices, Settings, total-EQ state, empty application state, conditional EQ shutdown, and hidden scroll indicators.
- A five-second runtime sample showed the main thread waiting for events rather than performing periodic HAL queries after the refresh refactor.
- Silent QA kept system volume at 0% and did not play audio.

## Downloads

- `AudioFlow.dmg` — drag-to-install disk image.
- `AudioFlow-macOS.zip` — portable application archive.
