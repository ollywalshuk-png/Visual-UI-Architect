# Visual UI Architect — Roadmap & Phase Tracker

Single source of truth for phase status. Update the **Status** column as work
lands. `done` = built, `swift build` clean, `swift run VUACheck` green, and
visible/integrated. `partial` = some sub-items shipped, gaps listed. `planned`
= not started (placeholder so it isn't forgotten).

Verification gate for every phase: `swift build` → `swift run VUACheck` →
rebuild app bundle → update README → commit when green.

| Phase | Title | Status | Notes |
|------:|-------|--------|-------|
| 1–2 | Foundation + repository round-trip | ✅ done | `90db395` |
| 3 | Asset library + plugin components | ✅ done | `ab23f44` |
| 4 | Controls library + constraints + asset rendering | ✅ done | `466847c` |
| — | Layer reordering / z-order | ✅ done | `a248532` |
| 5 | Export integrity pipeline | ✅ done | `cc64054` |
| 6 | `.vuaproj` persistence | ✅ done | `2313da0` |
| 7 | Shapes, gradients, groups, multi-select, clipboard, presets | ✅ done | `12df2d3` |
| 8 | Canvas workflow (zoom/grid/rulers/guides/snap) | ✅ done | `9750b21` |
| 9 | Document safety (autosave, recovery, snapshots, save-before-close) | ✅ done | `e04bd58`† |
| 9+ | Doc-safety gaps: save-before-open/new, two-window, recovery conflict | ✅ done | recovered baseline |
| 10 | Repo / Workspace safety (`WorkspaceEngine`, `WorkspaceContext`) | ✅ done | recovered baseline |
| 11 | Build Intelligence (`BuildIntelligenceEngine`) | ✅ done | lifecycle, toolchain, lockfile, failure explainer |
| 12 | Source / Asset / Layer hardening | ✅ done | HardeningValidator + SourceSafety preflight |
| 13 | Handoff Generator (`HandoffGeneratorEngine`) | ✅ done | 7 modes, deterministic, dirty-state aware |
| 14 | UI Quality Engine | ✅ done | density/spacing/contrast/a11y/noise scores + fixes |
| 15 | Component System (`ComponentEngine`) | ✅ done | masters + instances + propagation + cycle detection |
| 16 | Auto Layout / Responsive Layout | ⬜ planned | stacks/grids/breakpoints |
| 17 | Design System Manager (`DesignSystemEngine`) | ⬜ planned | tokens + theme |
| 18 | Interaction / Behaviour Engine (`UIBehaviourEngine`) | ⬜ planned | triggers/actions/bindings |
| 19 | State Variant System | ⬜ planned | empty/loading/error/hover/disabled |
| 20 | Preset expansion to 50+ | ✅ done (P16) | 250 advanced control presets (50× knob/fader/slider/button/toggle) shipped in Phase 16 |
| 21 | Target App Injection (`TargetAppInjectionEngine`) | ⬜ planned | inject into real repo |
| 22 | Repository Intelligence | ⬜ planned | view/asset/dependency graphs |
| 23 | Advanced SwiftUI round-trip | ⬜ planned | state/nav/list/form parsing |
| 24 | Build / Release pipeline | ⬜ planned | stages/artifacts/release notes |
| 25 | Performance / large-project support | ⬜ planned | 10k+ layers, incremental |
| 26 | App UX polish | ⬜ planned | welcome, palette, marquee, sticky rulers |
| 27 | Drawing tool hardening | ⬜ planned | DrawingTool abstraction, Escape cancel |
| 28 | Codebase awareness | ⬜ planned | repo/app/package classification |
| 29 | Plugin / AU expansion | ⬜ planned | AUParameter, MIDI CC, automation |
| 30 | Local review / commenting | ⬜ planned | layer comments, TODO markers |
| 31 | Security / privacy / licensing | ⬜ planned | privacy + licence reports |
| 32 | Backup / archive / portability | ⬜ planned | zip export, restore, integrity |
| 33 | Deployment / distribution | ⬜ planned | bundle/signing/notarisation readiness |

### Re-sequenced delivery track (user-numbered phases)
| Phase | Title | Status | Notes |
|------:|-------|--------|-------|
| P15 | Component System | ✅ done | `47916db` |
| — | App launch fix (exec bit) | ✅ done | `3e7a7fb` |
| P16 | Advanced control presets (250) | ✅ done | `cec98f3` |
| P17 | Functional asset metadata | ✅ done | role/function/binding on assets; metadata-aware drop; diagnostics |
| P18 | Existing UI import / screen loader | ✅ done | import SwiftUI file/repo → candidates+confidence → editable layers → hash-guarded apply |
| P19 | Control asset library expansion | ✅ done | 120 functional control assets: 20× knob/fader/slider/button/switch/meter, metadata + live previews |
| P20 | Control behaviour engine | ✅ done | behaviour profiles + inspector binding/MIDI/automation controls + codegen metadata comments |
| P21 | Refined line tool | ✅ done | line geometry, dashes/dots/caps/joins/arrows/connectors/snap metadata + diagnostics |
| P22 | Existing UI import polish | ✅ done | explicit temporary-layer import, provenance display, no-anchor apply blocking |
| P23 | Asset transform system | ✅ done | scale/flip/crop/blend/texture-hook metadata + inspector/codegen/diagnostics |
| P24 | Raster drawing tool | ✅ done | non-destructive paint strokes + PNG export asset + diagnostics |
| P25 | Vector / SVG drawing tool | ✅ done | vectorPath layer, anchors/handles, SwiftUI Path, SVG export + diagnostics |
| P26 | Advanced SwiftUI round trip | ✅ done | preview-only apply, partial-file diffs, line anchors, unsupported-region diagnostics, CRLF preservation |
| P27 | Component variants & overrides | ✅ done | variants, inherited values, local overrides, locked properties, variant-aware codegen |
| P28 | Design token system | ✅ done | colours, typography, spacing, radius, shadows, gradients, materials + token-aware codegen |
| P29 | Target App Injection v2 | 🔜 next | repo/file selection, injection preview, build validation, rollback |
| P30 | Existing App View Graph | ⬜ planned | view/component/dependency graph, source links, search, diagnostics |

† **History note (2026-06-09):** the original `.git` directory was lost when
the project was restored from a Google Drive zip export (Drive strips
dot-directories). All commit hashes above for Phases 1–9 refer to that lost
history and exist only as a record. The repository was re-initialised from the
recovered source — verified `swift build` clean and VUACheck 154/0 at recovery
— starting at commit `f86cd8b` ("Recovered baseline"). Lesson: back up the
repo with `git bundle` or push to a remote, not via folder-zip exports.

## Standing rules
- Local-first, no paid/cloud deps, no telemetry.
- Keep SwiftSyntax for round-trip (no regex parsing).
- Don't delete modules without an equivalent replacement.
- Never commit a failing build; never hide validation/build/export safety.
- Toolchain: Swift CLT only (no Xcode) → verify with `swift run VUACheck`,
  not `swift test`; generated code avoids the `#Preview` macro on export.
