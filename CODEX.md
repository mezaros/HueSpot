# HueSpot Development Notes

This document explains how HueSpot is structured, why key implementation choices were made, and where to modify behavior safely.

> Maintainer note: this document was generated and maintained by Codex as the technical handoff/reference guide for this codebase.

## Overview

HueSpot is a macOS menu bar utility that:
- Watches a global activation key
- Samples the pixel under the mouse while the key is held
- Displays a floating HUD with multiple naming systems
- Optionally copies formatted color values on double-press

The app is intentionally lightweight and avoids heavyweight capture/session frameworks for this use case.

## Architecture

### Entry and app shell
- `HueSpot/main.swift`
- `HueSpot/AppDelegate.swift`

`main.swift` uses an `NSApplication` entry point (not `@main` SwiftUI App) because this is a menu bar-first accessory app.

`AppDelegate` owns:
- `NSStatusItem` menu bar icon/menu
- Settings window lifecycle
- About panel action
- app start/stop hooks into `AppModel`

### State and orchestration
- `HueSpot/AppModel.swift`

`AppModel` is the single source of truth for runtime state:
- hotkey configuration
- sampling state
- current sample + names + hex
- overlay visibility toggles
- clipboard format and double-press behavior
- launch-at-login setting

It coordinates:
- `HotkeyManager` for key down/up events
- `ScreenCaptureSampler` for pixel reads
- `ColorNamer` for naming/classification
- `HUDWindowController` for overlay updates

### Global hotkey handling
- `HueSpot/HotkeyManager.swift`
- `HueSpot/Hotkey.swift`
- `HueSpot/HotkeyRecorder.swift`

Approach:
- Carbon event hotkey registration for standard key combos
- Polling fallback for reliability and modifier-only keys (especially right-side modifiers)
- Side-specific modifier masks for left/right differentiation

Reasoning:
- Modifier-only keys are not consistently reliable via Carbon events alone.
- Poll fallback keeps behavior consistent across keyboards/layouts and app focus states.

### Screen sampling
- `HueSpot/ScreenCaptureSampler.swift`

Approach:
- 1x1 sample rect under cursor
- CoreGraphics composited capture (`CGWindowListCreateImage` via symbol lookup)
- Convert into sRGB RGBA buffer before sampling

Reasoning:
- Captures what is visually composited on screen.
- Keeps implementation simple and performant for continuous sampling.

### Naming pipeline
- `HueSpot/ColorNamer.swift`
- `HueSpot/WikipediaColorData.swift`

For each sample, HueSpot produces:
1. **Simple Color Name** (minimal controlled vocabulary + optional clarifying parenthetical)
2. **ISCC-NBS Extended Name** (exact or nearest with ` (closest)`)
3. **Web/Wikipedia Name** (CSS exact first, then Wikipedia exact, else nearest with ` (closest)`)

Design goals:
- Keep top-line naming human-intuitive and low-ambiguity
- Preserve deterministic behavior for edge colors
- Prefer canonical CSS names when exact

### HUD and settings UI
- `HueSpot/HUDWindowController.swift`
- `HueSpot/HUDView.swift`
- `HueSpot/SettingsView.swift`

Mixing SwiftUI + AppKit is intentional and minimal:
- **AppKit** where macOS system integration is required:
  - menu bar item (`NSStatusItem`)
  - non-activating floating panel (`NSPanel`)
  - app lifecycle and settings window ownership
- **SwiftUI** for view rendering and state-driven UI composition:
  - settings form
  - HUD content
- **Bridge only where necessary**:
  - `NSViewRepresentable` for hotkey recording input capture

## Permissions model

HueSpot checks screen recording access with `CGPreflightScreenCaptureAccess()` and requests with `CGRequestScreenCaptureAccess()` only when explicitly requested.

If sampling detects permission-like capture failures, sampling is blocked until permission is revalidated (prevents prompt loops and repeated failing capture attempts).

## Clipboard behavior

Double-press detection:
- Two activation presses within `0.45s`
- Copies selected format to pasteboard
- Shows temporary HUD feedback
- On release, HUD performs a short fade-out when copy feedback was triggered

## Launch at login

Uses `SMAppService.mainApp` (macOS 13+).
- Setting persisted in user defaults
- Registration failures automatically roll back the toggle state

## Tests

- `HueSpotTests/HueSpotTests.swift`

Current tests cover:
- exact CSS naming behavior
- ISCC white behavior for pure white
- red/blue sanity checks for problematic swatches
- teal parenthetical coverage for known teal hexes

## Scheme behavior

Scheme pre/post actions are configured to:
- stop prior running HueSpot
- sync the built app to `~/Applications/HueSpot.app`
- launch via `open -na ~/Applications/HueSpot.app`

This stabilizes identity/path for macOS permission handling during local development.

## Maintenance guidelines

When changing HueSpot, prefer these invariants:
- Keep `AppModel` as orchestrator; avoid scattering side effects into views.
- Keep hotkey behavior deterministic for modifier-only keys.
- Preserve CSS exact-name precedence before nearest matching.
- Do not add new TCC requirements unless strictly necessary.
- Keep AppKit usage constrained to system integration boundaries.

If behavior appears inconsistent, first verify:
- active signing identity is stable
- app launch path remains `~/Applications/HueSpot.app`
- screen recording permission entry matches the running executable identity
