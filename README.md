# mxDOS

![License: GPL-2.0](https://img.shields.io/badge/license-GPL--2.0-blue)
![Platform: iOS](https://img.shields.io/badge/platform-iOS-lightgrey)
![iOS 15+](https://img.shields.io/badge/iOS-15%2B-informational)
![Status: Development](https://img.shields.io/badge/status-development-orange)

**Play your DOS game library on iPhone.** mxDOS is a full DOS emulator for iOS, powered by [DOSBox Staging](https://github.com/dosbox-staging/dosbox-staging), with a native touch control overlay built for handheld play.

<img src="docs/demo.gif" width="280" />

---

## Features

- **Touch overlay**: D-pad and action buttons (Enter, Esc, Space, F1, F5) inject real SDL keyboard events; each button has press-state visual feedback with per-key colours
- **Game library**: scans the app's Documents folder on every launch; auto-generates a `dosbox.conf` for any subfolder containing a `.bat` or `.exe` file
- **In-game switching**: home button (⌂) slides in a game picker while the current game keeps running; switches by remounting and issuing a warm reboot
- **Multi-disc support**: drop CD images (`.cue` / `.iso` / `.img`) into a `CD/` subfolder and they are mounted automatically as drive D:
- **Safe-area aware layout**: touch controls reflow between portrait and landscape, avoiding the home indicator and notch

---

## Build

See **[docs/build.md](docs/build.md)** for full step-by-step instructions.

In brief: clone DOSBox Staging (v0.82.2) and SDL2 into the repo root, run `scripts/build-ios-deps.sh` to build the audio libraries, cross-compile both upstream libraries for iOS ARM64 using the cross file in `cmake/`, then open `mxDOS/mxDOS.xcodeproj` in Xcode.

---

## Adding games

1. Connect your iPhone to your Mac and open Finder.
2. Select your device → **Files** → **mxDOS**.
3. Drag a game folder into the app's Documents directory and launch the app.

mxDOS scans each subfolder for a `.bat` launcher (preferred) or `.exe` file and auto-generates a `dosbox.conf`. To override, place your own `dosbox.conf` in the game folder and mxDOS will use it as-is.

### Folder layout

```
Documents/
├── MyGame/
│   ├── GAME.EXE
│   └── dosbox.conf        ← optional; auto-generated if absent
│
└── MyDisc Game/
    ├── LAUNCH.BAT
    └── CD/
        ├── DISC1.cue      ← mounted as drive D: automatically
        └── DISC1.bin
```

---

## Powered by

mxDOS stands on the shoulders of these projects:

| Project | Role |
|---------|------|
| [DOSBox Staging](https://github.com/dosbox-staging/dosbox-staging) | DOS emulation core (x86 CPU, VGA, OPL audio, DOS layer) |
| [SDL2](https://github.com/libsdl-org/SDL) | Cross-platform video, audio, and input abstraction |
| [Opus / opusfile / libogg](https://opus-codec.org/) | CD audio playback for Opus-encoded OGG tracks |

Thank you to the DOSBox Staging team and all contributors to these projects.

---

## License

GPL-2.0. See [LICENSE](LICENSE).

Game files are not included and remain the property of their respective copyright holders.
