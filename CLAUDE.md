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

### Indentation Rules - CRITICAL

**All code in this project uses TABS**, with ONE critical exception:

- **Treeswift code (everything except PeripherySource/)**: Use **TABS** for indentation
  - All Swift files in the main project
  - All configuration files (unless otherwise specified in .editorconfig)

- **PeripherySource/ directory ONLY**: Use **4 SPACES** per indentation level
  - This directory contains a git subtree to the upstream Periphery repository
  - The upstream project uses spaces, so we must match that convention
  - This applies to ALL files within PeripherySource/ and its subdirectories

**Use .editorconfig** - Check the project's `.editorconfig` file for specific settings:
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

**CRITICAL: Two categories of changes — different workflows.**

### Treeswift-specific changes (apply directly here)

Changes required *only* for Periphery to work as a library consumed by Treeswift (e.g., exposing public APIs, adding progress delegates, end-position tracking). These are applied directly to the subtree in this repository.

When making such changes, follow the diff minimization strategy and document all changes in [PeripherySource/periphery/README_Treeswift.md](PeripherySource/periphery/README_Treeswift.md).

### General analysis changes (DO NOT apply here)

Changes to Periphery's core analysis logic (e.g., new scan rules, bug fixes in existing mutators, new detection patterns) must NOT be applied directly to the subtree. These belong in the upstream Periphery repository (danwood/periphery). Instead:

1. **Stop and plan** — identify which upstream branch the change belongs on
2. **Apply the change in the upstream repository** (danwood/periphery)
3. **Pull the subtree** to bring the change into Treeswift via `git subtree pull`

This ensures analysis improvements are properly tracked upstream and avoids divergence that complicates future subtree pulls.

See [PeripherySource/periphery/README_Treeswift.md](PeripherySource/periphery/README_Treeswift.md) for complete details on diff minimization patterns, current modifications, update workflow, and git subtree management.
