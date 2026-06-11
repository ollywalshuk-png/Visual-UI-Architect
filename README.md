# Visual UI Architect

A developer-focused **visual UI engineering environment** for Apple platforms.
Manipulate real application layouts on a Photoshop/Figma-style canvas while the
system keeps design and production-quality code in sync.

> Visual-first code engineering — not a mock-up tool, not low-code.

## Status

- **Phase 1 — Foundation:** runnable macOS app, modular engines, visual editing,
  SwiftUI codegen, validation, git, AI abstraction.
- **Phase 2 — Repository round-trip (done):** open existing SwiftUI files/repos,
  parse views into layers with **SwiftSyntax** (no regex), edit visually, and
  **apply changes back to source preserving comments/formatting**. External edits
  (e.g. from Xcode) refresh the canvas automatically. Safe-apply pipeline:
  validate → write → `swift build` → git diff.
- **Phase 3 — Assets + plugin components (done):** asset library (import
  PNG/JPEG/SVG/PDF, search, tags, lock, replace, **drag onto canvas**); plugin
  controls (**knob/fader/meter/slider/switch**) as first-class layers carrying
  **AU parameter metadata** (id, range, default, unit, steps) edited in the
  inspector and emitted into generated SwiftUI; **asset name write-back** to
  source via the safe-apply pipeline.
- **Phase 4 — Controls library + constraint editor (done):** a real reusable
  SwiftUI control library (**`VUAControls`**: `KnobView`, `FaderView`,
  `MeterView`, `ControlView`) that generated code `import`s and parameterises
  with each control's range/default/label; a **visual constraint editor**
  (pin edges, center, fix size) on top of `ConstraintEngine`, with a *Resolve*
  action that re-lays a layer for the current size. A `ControlsExample` target
  compiles generated-style code against the library so the API can't drift.
- **Phase 5 — Export Integrity Pipeline (done):** generated SwiftUI is now
  **portable and target-buildable**. The new **`ExportIntegrityEngine`** writes
  a self-contained SwiftPM package containing the generated view, every
  referenced image (SwiftSyntax-scanned, sanitised, copied), the
  **`VUAControls` sources** as a local module, an asset manifest, an AU
  **parameter manifest**, and a human-readable export report. Diagnostics
  cover missing/unresolved assets, duplicate filenames, unsupported formats,
  unsafe filenames, placeholder parameters, unbound controls, and
  unsatisfiable imports. The verification harness exports a Trinity8-style UI
  to a temp dir and **runs `swift build` on the exported package**, so the
  test fails if generated code ever stops compiling outside Visual UI Architect.
- **Phase 6 — Persistence (done):** projects save as a **`.vuaproj` document
  bundle** (`document.json` + `Assets/`) — a single self-contained item that
  travels between machines with the layout *and* every imported image. New
  `PersistenceEngine`. Standard File menu (`⌘N` / `⌘O` / `⌘S` / `⌘⇧S` / Open
  Recent), dirty-state tracking, "Edited" marker in the title bar, and
  **auto-reopen of the last document on launch**. Imported assets are copied
  into the bundle on save so the project survives the original import path
  going away.
- **Phase 7 — General-purpose UI tools (done):** Visual UI Architect is no
  longer plugin-only. New layer kinds — **groups**, **shapes**
  (rectangle/rounded/ellipse/capsule/star/divider/card/glass/callout),
  **lines/arrows**, **polygons/stars**, **gradients**, and **masks** — each
  with fill/stroke/corner-radius/opacity/**shadow**/**blur**/**rotation**, plus
  **layer roles**, notes, and tags. **Clipboard** (cut/copy/paste with fresh
  ids), **multi-selection** (shift/⌘-click, group transform, align/distribute),
  **group/ungroup**, full **z-order** (front/back/forward/backward), and a
  **23-preset library** (app screens, panels, cards, dashboards, forms, modals,
  and plugin blocks like oscillator/filter/ADSR/mixer). Code generation emits
  real SwiftUI shapes, `Path`s, `LinearGradient`/`RadialGradient`/`AngularGradient`,
  `.clipShape`/`.mask`, `.shadow`/`.blur`/`.rotationEffect` — anchors preserved.
  The repository parser maps `Rectangle`/`RoundedRectangle`/`Circle`/`Capsule`/
  `Divider` to shape layers (SwiftSyntax, no regex). Validation gained
  structural checks (zero-size, invisible, transparent, invalid polygon,
  missing asset, empty group, inverted mask). The harness exports a
  shapes+gradient+group+star UI and **`swift build`s it** to prove portability.

- **Phase 8 — Canvas workflow (done):** professional canvas navigation —
  **zoom to fit / 100% / to-selection**, pinch-to-zoom, and zoom ± with a
  shared clamp; a **grid overlay** with adjustable spacing and **snap-to-grid**;
  draggable **ruler guides** (double-click to remove) that layers snap to;
  **rulers** with auto-spaced "nice" tick steps that never crowd at any zoom;
  and live **alignment guides** while dragging (edge/center). The snap maths
  (`CanvasGrid`, `CanvasViewport`, `CanvasRuler`, `AlignmentGuides`) live in
  `CanvasEngine` and are unit-checked.

- **Phase 9 — Document safety (done):** **autosave** (timer → recovery file) and
  **crash recovery** (a restore prompt on next launch if the previous session
  didn't exit cleanly); **save-before-close** prompt (`⌘W` Close command →
  Save / Don't Save / Cancel); **version snapshots** stored inside
  `.vuaproj/Snapshots/` (captured on every save, pruned to the newest 25, with a
  restore browser); and **corrupted-document diagnostics** (`VUABundle.diagnose`)
  so a damaged or incomplete bundle reports a clear reason instead of crashing.
  Gap-closure follow-up: **save-before-open / save-before-new** guards routed
  through the same dirty-check as Close; **recovery conflict classification**
  (recovery newer / older than the saved project, surfaced in the restore
  prompt); and an **open-document registry** that detects the same `.vuaproj`
  being edited from two windows/instances.

- **Phase 10 — Repo / workspace safety (done):** new **`WorkspaceEngine`**.
  `WorkspaceResolver` scans a chosen root and builds a **`WorkspaceContext`**
  (repo root, branch, latest commit, dirty state, Package/xcodeproj/xcworkspace
  inventory, source files, asset roots, scan timestamp, confidence score) with
  diagnostics for the dangerous cases: **nested/multiple repos**, multiple
  `Package.swift`, **generated-export-folder selected as source repo**,
  `.build`/dependency folders selected accidentally, dirty tree, detached HEAD,
  merge/rebase in progress, git lock files, and **stale scans** (file changed
  or deleted after parse). The context **refreshes before Apply-to-Source** and
  blocks/warns instead of writing into the wrong place. A **Workspace
  Diagnostics** panel (toolbar) shows the active repo/branch/dirty badges and
  every detected warning.

- **Phase 11 — Build intelligence (done):** new **`BuildIntelligenceEngine`**.
  Models the build lifecycle (Workspace Resolve → Package Resolve → Swift Build
  → Verify → Export Build → App Bundle → Artifact) and build kinds
  (dev/debug/release/CI/staging/production/export-validation); probes the
  **toolchain** (Swift version, CLT-only vs full Xcode); inspects packages
  (missing `Package.swift`, missing/**stale `Package.resolved`**, cold `.build`
  cache); scans generated source for **imports that won't resolve**, a
  VUAControls dependency that isn't bundled, and `#Preview` on CLT-only
  machines; formats the **exact repeatable build command**; and translates raw
  build failures into **plain-English explanations** (no-such-module, manifest
  parse, fetch failures, linker errors, name collisions…). A **Build
  Diagnostics** panel (toolbar ▸ hammer) shows context, pipeline, command, and
  diagnostics.

- **Phase 12 — Source / asset / layer hardening (done):** a **`HardeningValidator`**
  (duplicate layer IDs, duplicate source anchors, off-canvas layers, hidden-parent
  traps, fully-transparent gradients, background-above-controls and
  control-behind-opaque-panel z-order mistakes, asset name collisions — exact,
  case-only, and sanitised — plus missing/external asset files) and a
  **`SourceSafety` preflight** that runs before every Apply-to-Source: merge-conflict
  markers, read-only/missing files, **external-edit detection via SHA-256 source
  hashes**, CRLF/tab fingerprints (preserved on write), and **anchor sanity**
  (each targeted anchor must exist exactly once). The safe-apply pipeline gained
  a blocking **preflight stage** between validate and write.

- **Phase 13 — Handoff generator (done):** new **`HandoffGeneratorEngine`** —
  renders a deterministic **HANDOFF.md** (mission, verified repo/build/check
  state, module map, capability inventory, warnings, limitations, safety rules,
  recovery commands, roadmap, next work) in seven modes (full project /
  current document / bug-fix / next-phase / export / AI model / developer).
  Toolbar ▸ **Handoff** previews it, copies to clipboard, or writes it into
  the repository root. Dirty working trees are flagged inside the document
  so a handoff can never silently claim a clean state.

- **Phase 14 — UI quality engine (done):** new **`UIQualityEngine`** — answers
  *"is this a good interface?"*, not just *"does it build?"*. Heuristic checks:
  information **density** (controls per screen/area), **8-point-grid** and
  spacing consistency, **alignment near-misses** (1–3 px), **WCAG contrast**
  (text vs effective background, AA thresholds), **tap targets** (44 pt on
  touch devices only), **icon-only buttons** without labels, **text
  overflow/truncation** and unbreakable URL runs, **palette size**, effect
  **noise** (shadow/blur/gradient saturation), and missing hierarchy on busy
  screens. Produces 0–100 **scores with grades** (Design / Layout / Calm /
  Accessibility / Responsive + overall), top-five fixes, and per-finding
  recommendations with layer selection. Toolbar ▸ **Quality**.
- **Phase 15 — Component system (done):** new **`ComponentEngine`** — real
  reusable components, not presets. Create a master from the current selection,
  insert instances, **detach** instances, and **propagate** master edits to
  every instance with a single click. Detects **circular references** (direct
  and indirect, via a forward-reachability walk), diagnoses missing masters,
  duplicate names, and empty bodies. Cloning a layer preserves its
  `componentID` so paste keeps the link. Documents save/load components inside
  `.vuaproj`, with backwards-compatible decoding for older files (no
  `components` key → empty array). Generated SwiftUI emits one
  `<Name>ComponentView` struct per master and replaces instance bodies with a
  single constructor call; the export pipeline `swift build`s the result so
  components are proven portable. Sidebar tab **Components** lists masters
  with instance counts, diagnostics, and inline actions
  (insert / update-all / rename / delete).

- **Phase 16 — Advanced control presets (done):** **250 first-class control
  presets** — 50 each for knobs, faders, sliders, buttons, and switches —
  built combinatorially from 10 named **style families** (Classic, Minimal
  Flat, Modern Pro, Vintage, Neon, Glass, Pill, Mono, Danger, Success)
  × 5 size/parameter variants per kind. Every preset has unique id + unique
  name, real styling (background/accent/border/corner-radius/shadow/font
  weight), and sensible default **AU parameter metadata** (id, range, unit,
  default) for behaviour/binding work that follows. New sidebar tab
  **Controls** with a segmented kind picker, a horizontally-scrollable
  family filter, search across name/family/tags, and an adaptive grid of
  **live SwiftUI thumbnails** (no PNG generation — the renderer that draws
  the canvas draws the previews). Tap inserts at canvas centre.

- **Phase 17 — Functional asset metadata (done):** imported assets become
  functional controls, not just images. Each `Asset` carries optional
  **`AssetMetadata`** — role (backplate / knob cap / fader cap / track / meter /
  button / switch / decoration / icon / texture), function, interaction type,
  **rotation** and **drag** envelopes, and a production **control binding**
  (parameter id, range, default, unit, MIDI CC, AU parameter id, automation,
  stepped/continuous). Dropping an asset now resolves its **layer kind**
  (knobCap → `.knob`, faderCap → `.fader`, …) and attaches a `ControlMetadata`
  binding so generated SwiftUI emits a real `KnobView`/`FaderView`. The asset
  browser gains a per-asset **Functional Metadata** editor with role badges and
  live diagnostics (missing parameter id / range, invalid or inverted range,
  default out of range, MIDI CC out of 0–127, missing step count, role↔function
  mismatch). Backwards-compatible: legacy `Asset` JSON without `metadata`
  decodes unchanged.

- **Phase 18 — Existing UI import / screen loader (done):** a user-facing
  **Import Existing UI** workflow (File ▸ Import Existing UI… `⇧⌘I`, and an
  **Import UI** toolbar button) that turns a real app's SwiftUI into editable
  layers. Choose a `.swift` file **or** an app/repo folder; the engine scans
  with **SwiftSyntax** (no regex) for `struct … : View` / `var body`, ignoring
  preview-only helpers, and lists **import candidates** with a **confidence
  score** (supported ÷ total view calls), supported/unsupported counts, anchor
  presence, and warnings. Importing reconstructs the layer tree via the existing
  parser and records provenance — source path, **content hash** (FNV-1a), and
  view name. Unsupported constructs are counted and surfaced rather than
  silently dropped. Round-trip safety: **Apply to Source blocks when the source
  file changed on disk since import** (hash mismatch) and re-syncs the hash
  after a successful write. Repo scanning detects `Package.swift`/`.xcodeproj`/
  `.xcworkspace` and the conventional `Sources`/`Views`/`UI`/`Components` folders.

- **Phase 19 — Control asset library expansion (done):** new functional
  **Control Assets** sidebar with 120 reusable assets: 20 each for knobs,
  faders, sliders, buttons, switches, and meters. Each asset has a stable id,
  category, asset role/function, default size, visual style metadata,
  behaviour hint, range/default/unit where relevant, accessibility label
  template, tags, live thumbnail preview, and layer creation support. These
  complement the Phase 16 preset browser rather than replacing it; inserted
  assets create real non-zero layers with `ControlMetadata` so generated
  SwiftUI still emits buildable controls including `MeterView`.

All engines compile and pass the verification harness (`swift run VUACheck`, 331 checks).

## Requirements

- macOS 14+
- Swift 6 toolchain (Command Line Tools is enough — Xcode optional)

## Build & run

```bash
# Build a double-clickable .app (no Xcode needed)
./Scripts/make_app.sh
open "dist/Visual UI Architect.app"

# Or run directly during development
swift run VisualUIArchitect
```

## Verify

```bash
# Toolchain-independent engine checks (works without Xcode)
swift run VUACheck

# Full XCTest suite (requires Xcode or a CI toolchain with XCTest)
swift test
```

## Architecture

Modular Swift Package — no monolith. Each engine is a single-responsibility
target depending only on the shared domain layer (`VUACore`).

| Module | Responsibility |
|---|---|
| `VUACore` | Platform-independent domain models (`Layer`, `Document`, geometry, color, constraints, assets, devices). `Codable`/`Sendable`. |
| `LayerEngine` | Tree mutation, hit-testing, align/distribute, snapping. |
| `CanvasEngine` | Drag/resize/marquee interaction geometry. |
| `AssetEngine` | Asset library: import PNG/JPEG/SVG/PDF (retina-aware), replace, tag, filter. |
| `LayoutEngine` | Responsive adaptation, size classes, breakpoints. |
| `ConstraintEngine` | Pin/center/proportional constraint solving. |
| `ValidationEngine` | WCAG contrast, touch targets, overlap/clipping, accessibility. |
| `GitEngine` | Local-first git: status/diff/commit/branch/history/rollback. |
| `CodeGenEngine` | Production-quality **SwiftUI** generation (UIKit/AppKit/React/Flutter/Compose scaffolded). |
| `AIEngine` | Provider-abstracted `AgentAdapter` — suggestions only, never edits files. |
| `PreviewEngine` | Flattened, absolutely-positioned render model for any front-end. |
| `RepositoryEngine` | **SwiftSyntax** parse (source → layers), source-fidelity write-back, repo scanner, file watcher, safe-apply pipeline. |
| `VUAControls` | Shipping reusable SwiftUI controls (`KnobView`/`FaderView`/`MeterView`/`ControlView`) that generated code imports. |
| `ExportIntegrityEngine` | Portable SwiftPM export: image-reference scanner (SwiftSyntax), asset copy + manifest, VUAControls source export, AU parameter manifest, diagnostics, report. |
| `PersistenceEngine` | `.vuaproj` bundle I/O, recent documents, **version snapshots**, **autosave/crash recovery** (with newer/older conflict classification), open-document registry, corrupted-doc diagnostics. |
| `WorkspaceEngine` | Repo/workspace safety: `WorkspaceResolver` → `WorkspaceContext` (repo root, branch, commit, dirty state, package inventory, confidence score) + wrong-repo/nested-repo/stale-scan/export-folder diagnostics, refreshed before every apply. |
| `BuildIntelligenceEngine` | Build lifecycle model, toolchain/package/lockfile diagnostics, repeatable command formatting, generated-import scanning, plain-English build-failure explanations. |
| `HandoffGeneratorEngine` | Deterministic HANDOFF.md generation (7 modes) with verified-state table, safety rules, and recovery commands. |
| `UIQualityEngine` | Heuristic interface-quality assessment: density, grid/spacing, alignment, WCAG contrast, tap targets, overflow, palette/effect noise → scored report with fixes. |
| `PresetEngine` | Reusable, insertable layout presets (app screens, panels, cards, dashboards, forms, plugin blocks). |
| `VisualUIArchitect` | SwiftUI app (MVVM): canvas, layer panel, repository browser, inspector, validation, toolbar. |

### Design principles

- **Bidirectional sync** — every layer carries a `CodeBinding` anchor so generated
  code round-trips to source.
- **Local-first & private** — no cloud upload, no telemetry, no remote code execution.
- **AI is optional and non-destructive** — it proposes `ProposedChange` values the
  user must approve; the app applies them, never the adapter.
- **Validate before commit** — the code preview surfaces blocking validation errors.

## Repository round-trip (Phase 2)

In the app, switch the sidebar to **Repository**:

1. **Open Repo** (a folder) or **Open File** (a `.swift` view).
2. Pick a SwiftUI view — it's parsed into editable layers on the canvas.
3. Edit visually (move/resize/restyle).
4. **Apply to Source** → *Apply* (validate + write + diff) or *Safe Apply* (also runs `swift build`).
5. Review the result sheet (stages, git diff, build output), then commit when ready.

Editing the file externally (e.g. in Xcode) refreshes the canvas automatically.

Parser scope: `View` structs whose `body` uses stacks (`VStack`/`HStack`/`ZStack`/`Group`)
and common leaves (`Text`, `Button`, `Image`, `Slider`, `Toggle`, `Label`). Write-back
currently round-trips `.position`/`.frame` by `accessibilityIdentifier` anchor; all other
source is preserved byte-for-byte.

## Assets & plugin controls (Phase 3)

- **Assets** sidebar tab: **Import** PNG/JPEG/SVG/PDF, search by name/tag,
  right-click to assign/replace/tag/lock/delete, and **drag a thumbnail onto the
  canvas** to create an image (or a locked background for `bg`-tagged assets).
- **Add Layer ▸ Plugin Controls**: knob, fader, slider, meter, switch. Each gets
  default **AU parameter metadata** editable in the inspector's *AU Parameter*
  section (param id, display, min/max/default, unit, continuous/steps).
- Generated SwiftUI emits a `// AU param:` comment and a conventional control
  view (`KnobView`/`FaderView`/`MeterView`) you supply, keeping the anchor stable.
- **Apply to Source** also round-trips assigned image asset names back into
  `Image(...)` calls.

## Export Integrity Pipeline (Phase 5)

Toolbar ▸ **Export** opens the export panel.

1. Pick a destination folder, set the module name, and choose whether to
   bundle `VUAControls` (recommended — the export is self-contained).
2. Click **Export**. The pipeline:
   - generates SwiftUI (no `#Preview` macro, for CLT-portable builds);
   - scans the generated source with **SwiftSyntax** for every `Image("…")`
     reference and matches each to an imported asset (no regex);
   - copies asset files into `Sources/<Module>/Resources/`, sanitising
     unsafe filenames and rejecting duplicates;
   - copies `VUAControls` sources into `Sources/VUAControls/` as a local module;
   - writes `Package.swift`, an asset manifest, a parameter manifest, and a
     Markdown export report;
   - surfaces diagnostics for missing assets, unsupported formats,
     placeholder parameters, unbound controls, and unsatisfiable imports.

The verification harness exercises this end-to-end: it exports a
Trinity8-style UI to a temp directory and **runs `swift build` on it** so the
test fails if generated code ever stops compiling outside Visual UI Architect.

## Roadmap

Next: richer write-back (style/text/structural inserts), navigation parsing,
relative (layer-to-layer) constraints in the editor, device chrome frames,
**MIDI CC / automation binding** for AU parameters, an Xcode `.xcassets`
export route, additional code-gen targets, and a plugin API.
