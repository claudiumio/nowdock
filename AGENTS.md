# NowDock — AGENTS.md

Native macOS "now playing" companion that sits to the left of the Dock. Full plan: `PLAN.md`.

## Stack

- Swift 6.3 + SwiftPM, AppKit (window/system) + SwiftUI (panel content only). **No Xcode** on this machine — Command Line Tools only; never add an `.xcodeproj`.
- Deployment target macOS 14; Liquid Glass (`NSGlassEffectView`) behind `if #available(macOS 26, *)`.
- No third-party dependencies without asking first.

## Commands

- Build: `swift build`
- Test: `Scripts/test.sh` (Swift Testing, pure logic in `NowDockCore`; plain `swift test` fails with CLT-only)
- App bundle: `Scripts/build-app.sh` → `build/NowDock.app`
- Run: `Scripts/run.sh`

## Rules

- `Sources/NowDockCore/Contracts.swift` is the cross-module contract. Changing it means updating every consumer in the same change.
- `NowDockCore` must not import AppKit/SwiftUI.
- Event-driven only: no polling timers. The only allowed periodic work is the 1 Hz progress redraw and the 15 s position resync, both **only while playing and visible**.
- Never send AppleScript to a player that isn't running (it would launch it). Check `NSRunningApplication` first.
- AppleScript runs off the main thread on one serial queue; compile scripts once.
