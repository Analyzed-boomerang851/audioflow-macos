# Contributing to AudioFlow

Thank you for helping improve AudioFlow.

## Before opening an issue

- Search existing issues first.
- Include the macOS version, Mac model, AudioFlow version, and affected audio device.
- Describe the expected and actual behavior.
- Include reproducible steps and screenshots when useful.
- Never attach captured audio, private device identifiers, signing certificates, or account credentials.

## Development setup

```bash
git clone https://github.com/Pandachan98/audioflow-macos.git
cd audioflow-macos
swift build
```

Create a distributable local build without launching it:

```bash
./build-app.sh
```

## Pull requests

1. Create a focused branch from `main`.
2. Keep changes scoped and explain user-visible behavior.
3. Verify `swift build -c release` succeeds.
4. Test master volume, per-app volume, mute, device switching, menu bar behavior, localization, and both appearance modes when your change affects them.
5. Update documentation and `CHANGELOG.md` for user-facing changes.

By contributing, you agree that your contribution is licensed under the MIT License.
