# Contributing to Visual UI Architect

Thanks for helping improve Visual UI Architect. This project is a local-first
SwiftUI engineering tool, so contributions should keep the app buildable,
private by default, and safe around user source code.

## Before you start

- Branch from the latest `main`.
- Keep PRs focused on one feature, fix, or documentation improvement.
- Avoid paid services, telemetry, or cloud dependencies.
- Do not replace SwiftSyntax-based parsing with regular-expression parsing.
- Generated code must remain real, portable, and buildable.
- Check with the maintainer before adding license-dependent assets or code. This
  repository does not currently declare a license.

## Local setup

Requirements:

- macOS 14 or newer
- Swift 6 toolchain
- Xcode is optional for development, but useful for full XCTest support

Build the package:

```bash
swift build
```

Run the app while developing:

```bash
swift run VisualUIArchitect
```

Build a double-clickable app bundle:

```bash
bash Scripts/make_app.sh
open "dist/Visual UI Architect.app"
```

## Verification

Run the relevant checks before opening a PR:

```bash
swift build
swift test
swift run VUACheck
bash Scripts/make_app.sh
```

`swift run VUACheck` is the project-specific verification harness and should be
green for changes that touch engines, code generation, persistence, import,
export, repository safety, or validation.

## Pull requests

In the PR description, include:

- what changed
- why it changed
- how it affects users or contributors
- the verification commands you ran
- screenshots or recordings for visible UI changes

For code changes, prefer tests or `VUACheck` coverage that proves the behavior.
For documentation-only changes, say that no runtime checks were needed.

## Good first contribution areas

- CI and contributor onboarding
- focused XCTest or `VUACheck` coverage for existing engines
- documentation that explains real workflows
- bug reports with reproducible SwiftUI inputs and expected output
- small UI polish that does not change repository write safety
