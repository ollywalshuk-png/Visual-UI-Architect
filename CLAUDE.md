# Visual UI Architect — project guide

Visual UI engineering environment for Apple platforms (macOS/iPadOS/iOS/watchOS;
visionOS later). Photoshop-style layer canvas that stays synced with
production-quality generated code.

## Toolchain constraint

This machine has the **Swift 6 toolchain via Command Line Tools only — no full
Xcode**. Therefore:

- `xcodebuild` is unavailable. Build with **SwiftPM**.
- **XCTest and Swift Testing are not available** here. The `Tests/` XCTest
  targets are for Xcode/CI. For local verification use the `VUACheck`
  executable, which has no test-framework dependency.

## Common commands

```bash
swift build                       # build all
swift build --product VisualUIArchitect
swift run VUACheck                # run engine verification (use this to verify)
./Scripts/make_app.sh             # produce dist/Visual UI Architect.app
swift test                        # only works where XCTest exists (Xcode/CI)
```

## Architecture

Modular package; see README.md. Domain layer `VUACore` is platform-independent
(`Codable`/`Sendable`, no CoreGraphics). Engines depend only on `VUACore`
(+ `LayerEngine` where needed). App target `VisualUIArchitect` is SwiftUI MVVM
with `DocumentStore` as the single observable source of truth.

## Conventions

- Generated code must be real and compilable — never placeholders.
- AI (`AIEngine`) only proposes `ProposedChange`; the app applies on approval.
- Local-first: no network unless the user explicitly triggers git push/pull.
- `LayerEngine.Alignment` collides with SwiftUI's `Alignment` — fully qualify it
  in app code.
