# CLAUDE.md

Project-specific guidance for Claude Code when working with Treeswift.

## What This Project Is

Treeswift is a macOS SwiftUI GUI for the Periphery static analysis tool. It uses a **local modified Periphery package** at `PeripherySource/periphery/` (managed as git subtree, tracking upstream with local modifications).

**Read [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) for:** architecture details, file organization, dependencies, technical environment, Swift version, and git subtree workflow.

## Build Command

```bash
xcodebuild -project Treeswift.xcodeproj -scheme Treeswift build
```

## Command-Line Interface

Treeswift is a GUI application but can also be launched with command-line arguments for testing and automation. See README.md for complete CLI documentation.

## Code Formatting

**Use .editorconfig** - Always check the project's `.editorconfig` file for indentation settings. For this project:
- Swift files: Use **tabs** (not spaces) for indentation
- Markdown: Use spaces (2)
- JSON/YAML: Use spaces (2)

**Use .swiftformat** - This codebase is reformatted with swiftformat; use the settings in .swiftformat file.

## Key Project Constraints

### UI Layout
Configuration forms must follow [macOS layout guidelines](https://marioaguzman.github.io/design/layoutguidelines/):
- Right-aligned labels, left-aligned controls
- 20pt window margins, 6-12pt control spacing

### Utilities Location
Shared helper functions belong in `Utilities/` folder, not scattered across views (e.g., `DeclarationIconHelper.swift`, `TypeLabelFormatter.swift`)

## Modifying PeripherySource/periphery Files

When modifying files in `PeripherySource/periphery/`, follow the diff minimization strategy and document all changes in [PeripherySource/periphery/README_Treeswift.md](PeripherySource/periphery/README_Treeswift.md).

See that file for complete details on:
- Diff minimization patterns and examples
- Current modifications to Periphery
- Update workflow for new Periphery versions
- Git subtree management
