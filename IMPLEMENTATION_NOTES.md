# Periphery GUI - Implementation Notes

## Overview

This document describes the technical implementation details of Treeswift, a macOS SwiftUI application providing a graphical interface for the Periphery static analysis tool.

**For project-specific coding guidelines and constraints**, see [CLAUDE.md](CLAUDE.md).

This implementation invokes Periphery scanning functionality directly from a SwiftUI GUI application **without using shell commands**. The integration uses a locally modified version of the Periphery package as a local Swift package dependency.

## What Was Implemented

### 1. Local Periphery Package with Modifications

The `PeripherySource/periphery` directory contains a complete copy of the Periphery source code, managed as a **git subtree** tracking the upstream repository at <https://github.com/peripheryapp/periphery>. This directory is referenced as a **local Swift package** in the Xcode project.

#### Why Use a Local Modified Package?

The upstream Periphery Swift Package exposes only `PeripheryKit` as a library product. The internal scanning orchestration logic (`Scan`, `Project`, `ProjectDriver` implementations, etc.) is part of the `periphery` executable target and cannot be imported as libraries.

By maintaining a local modified copy of the package, we can:
- Expose additional library products (Configuration, SourceGraph, FrontendLib, etc.)
- Make internal classes public where needed (`Project`, `Scan`)
- Maintain our own modifications while staying synchronized with upstream
- Use the standard Swift Package Manager module system

#### Package Modifications

The local package at `PeripherySource/periphery/Package.swift` has been modified to expose additional library products:

**Added Library Products:**
- `Configuration` - Configuration management
- `SourceGraph` - Code graph representation
- `Shared` - Shell, SwiftVersion, common utilities
- `Logger` - Logging infrastructure
- `Extensions` - Utility extensions (FilePath, String, etc.)
- `Indexer` - Indexing pipeline
- `ProjectDrivers` - Project driver implementations
- `SyntaxAnalysis` - Swift syntax analysis
- `XcodeSupport` - Xcode project support
- `FrontendLib` - Frontend orchestration (Scan, Project classes)

**Target Structure Changes:**
- Split `Frontend` executable target into two targets:
  - `Frontend` (executable) - Contains only `main.swift`
  - `FrontendLib` (library) - Contains all other Frontend code (Scan, Project, etc.)
- Made `Project` and `Scan` classes public with public initializers

#### Periphery Source Code Modifications

Beyond the Package.swift modifications, the local Periphery source code has been enhanced with custom analysis capabilities and data structure improvements. These modifications fall into two categories:

**1. Data Structure Enhancements** (core functionality improvements)
- **Location range tracking**: Extended `Location` class with `endLine` and `endColumn` properties
  - Allows tracking the full source range of declarations (not just start position)
  - Modified `Location.swift` init to accept optional `endLine` and `endColumn` parameters
  - Updated hash calculation and equality comparison to include end positions
  - Modified `DeclarationSyntaxVisitor.swift` to capture end positions from Swift syntax nodes
  - Updated `SourceLocationBuilder.swift` to extract end line/column from syntax
  - Modified `SwiftIndexer.swift` to populate Location with end position data

**Modified Files Summary:**
- `Package.swift` - Added library product exports (10 new products)
- `Frontend/Project.swift` - Made class and methods public (5 lines)
- `Frontend/Scan.swift` - Made class public + return SourceGraph along with [ScanResult]
- `SourceGraph/Elements/Location.swift` - Added endLine/endColumn properties (~20 lines)
- `SourceGraph/Elements/Declaration.swift` - Minor tweaks for Dumper
- `Indexer/SwiftIndexer.swift` - Capture and use end positions (~20 lines)
- `SyntaxAnalysis/DeclarationSyntaxVisitor.swift` - Extract end positions from syntax (~25 lines)
- `SyntaxAnalysis/SourceLocationBuilder.swift` - Calculate end line/column (~10 lines)
- `PeripheryKit/Results/OutputFormatter.swift` - Minor formatting tweaks
- `ProjectDrivers/XcodeProjectDriver.swift` - Minor adjustments
- `XcodeSupport/Xcodebuild.swift` - Minor fixes

**Total Impact:** ~945 insertions, ~31 deletions across 10 files (primarily the Dumper class addition)

#### Git Subtree Management

The `PeripherySource/periphery` directory is managed as a **git subtree** tracking upstream Periphery changes.

**Setup (already done):**
```bash
# Add upstream remote
git remote add periphery-upstream https://github.com/peripheryapp/periphery.git

# Current baseline: clean upstream 5a4ac8b (post-3.4.0) at commit 4dd2a038
```

**To update to a newer released version of Periphery:**

See [PeripherySource/periphery/README_Treeswift.md](PeripherySource/periphery/README_Treeswift.md) for the complete update workflow.

```bash
# Example: Pull a specific version tag (e.g., version 3.5.0)
git subtree pull --prefix=PeripherySource/periphery periphery-upstream 3.5.0 --squash

# After the merge, verify local modifications are still present

# If modifications were overwritten, re-apply them
# Commit any re-applied modifications
git add PeripherySource/periphery/
git commit -m "Re-apply local modifications after periphery update to 3.3.0"
```

**To update to the latest development code (master branch):**

```bash
# Pull the latest master branch
git subtree pull --prefix=PeripherySource/periphery periphery-upstream master --squash

# After the merge, verify and re-apply local modifications if needed
git add PeripherySource/periphery/
git commit -m "Re-apply local modifications after periphery update to master"
```

**Git subtree workflow:**
- The `periphery-upstream` remote points to `https://github.com/peripheryapp/periphery`
- Updates are pulled with `git subtree pull` and squashed into a single commit
- Your local modifications are preserved in separate commits on top
- When merging new upstream versions, git will attempt to preserve your changes
- If conflicts occur, resolve them and re-apply modifications as needed

**Benefits of git subtree:**
- Keeps the complete periphery source code in your repository
- Tracks upstream changes and allows easy updates
- Preserves your local modifications in git history
- No need for separate submodule checkouts
- Simple merge workflow for pulling upstream changes
- The local package can be referenced directly in Xcode

**Source:** https://github.com/peripheryapp/periphery (Based on 3.4.0+ post-release commit 5a4ac8b, MIT License, managed as git subtree)

### 2. PeripheryScanRunner Wrapper

Created `PeripheryScanRunner.swift` which:
- Provides a clean Swift API for invoking scans
- Imports from local package libraries: `Configuration`, `Logger`, `Shared`, `PeripheryKit`, `SourceGraph`, `Extensions`, `FrontendLib`
- Uses `Scan` and `Project` classes from FrontendLib
- Returns `ScanResult` objects from PeripheryKit
- Runs scans asynchronously to avoid blocking the UI
- Includes custom `GUIShell` to fix PATH issues for GUI apps

```swift
let config = Configuration()
config.project = FilePath("/path/to/project.xcodeproj")
config.schemes = ["MyScheme"]
config.excludeTests = true

let results = try await scanner.runScan(configuration: config)
```

### 3. SwiftUI Interface

The application provides a complete macOS-native GUI for Periphery scanning with the following features:

#### Architecture
- **Views**: SwiftUI components organized in a NavigationSplitView (sidebar + detail)
- **Configuration Management**: Models and managers for storing/loading user configurations in UserDefaults as JSON
- **Periphery Integration**: Wrapper classes for invoking Periphery scans and querying project metadata
- **Utilities**: Shared helper functions in `Utilities/` folder (e.g., `DeclarationIconHelper`, `TypeLabelFormatter`)

#### Configuration Management
- Multiple named configurations stored in UserDefaults as JSON
- Each configuration stores project path, schemes, build arguments, and all Periphery options
- Configurations can be created, edited, deleted, and reordered
- Drag project files from Finder to sidebar to create new configurations
- Current selection is remembered across app launches

#### User Interface
- macOS-native NavigationSplitView with sidebar and detail areas
- Sidebar shows all configurations (labeled by project filename from NSWorkspace)
- Configuration form following [macOS layout guidelines](https://marioaguzman.github.io/design/layoutguidelines/):
  - Right-aligned labels with left-aligned controls
  - 20-point window margins, 6-12 point control spacing
  - Project selection via Choose button or drag-and-drop with visual feedback
  - Automatic scheme detection from xcodebuild with checkboxes
  - Build arguments and common options (exclude tests, verbose, etc.)
- Scan results displayed in Xcode-format output (text is selectable)
- Drag-and-drop support on both sidebar (new config) and form (set project)

#### Scheme Detection
- Automatically queries `xcodebuild -list -json` when project is selected
- Displays checkboxes for all available schemes
- Results cached in memory (cleared when app becomes inactive)
- Cache invalidated when user explicitly re-selects a project file

## Technical Solutions

### Technical Environment

**Swift Version:**
- Swift 6.2
- macOS 15+ deployment target
- Uses modern Swift concurrency (`SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)

**Sandbox:**
- The app does not use the App Sandbox (required for unrestricted file system access and command execution)

**Window Configuration:**
- Uses `.windowToolbarStyle(.unifiedCompact)` and `.windowStyle(.hiddenTitleBar)` to minimize title bar space
- Some title bar area remains visible due to SwiftUI/macOS limitations

**Data Persistence:**
- **Configurations**: Stored in UserDefaults as JSON
- **Scheme cache**: In-memory only, cleared when app becomes inactive
- **Current selection**: Remembered across app launches

### GUI App PATH Handling
GUI apps don't inherit the full shell PATH environment. The custom `GUIShell` class in `PeripheryScanRunner.swift` explicitly adds common developer tool paths to the environment before executing commands, ensuring `swift`, `xcodebuild`, and other tools can be found.

## Supported Project Types

All Periphery-supported project types work:
- ✅ **Xcode** projects (.xcodeproj, .xcworkspace)
- ✅ **SPM** (Swift Package Manager) projects
- ✅ **Bazel** projects
- ✅ **Generic** projects (with custom configuration)

## Architecture

```
ContentView (SwiftUI)
    ↓
PeripheryScanRunner
    ↓
Imports from Local Package:
    Configuration
    Logger, Shell, SwiftVersion (from Shared)
    SourceGraph
    FrontendLib (Project, Scan)
    Extensions
    ↓
Local Package Modules:
    ProjectDrivers (XcodeProjectDriver, SPMProjectDriver, etc.)
    Indexer (IndexPipeline, SwiftIndexer, etc.)
    PeripheryKit (ScanResult, ScanResultBuilder)
    ↓
External Package Dependencies:
    XcodeProj, SwiftSyntax, Yams, SwiftIndexStore, etc.
```

## Key Design Decisions

1. **Local Package Approach**: Uses a local modified Swift package instead of adding files to app target
   - Preserves module boundaries and proper Swift package structure
   - Allows clean imports with `import Configuration`, `import FrontendLib`, etc.
   - No need to modify periphery source files extensively

2. **Git Subtree for Version Control**: Manages the local package as a git subtree
   - Tracks upstream changes from periphery repository
   - Preserves local modifications in git history
   - Simple update workflow with `git subtree pull`

3. **Minimal Package Modifications**: Only modified Package.swift and made a few classes public
   - Added library product declarations for internal modules
   - Split Frontend executable into Frontend + FrontendLib
   - Made `Project` and `Scan` classes public

4. **Custom Integration Code**: Created `GUIShell` class in PeripheryScanRunner.swift to fix PATH issues for GUI apps

5. **Forward Compatible**: When Periphery updates:
   - Use `git subtree pull` to merge upstream changes
   - Verify local modifications are preserved
   - Re-apply if necessary (Package.swift changes, public modifiers)
   - Minimal conflicts since modifications are small and well-defined

## Using the Application

1. Build and run the Treeswift app
2. Create a new configuration:
   - Drag a project file (.xcodeproj or .xcworkspace) to the sidebar, or
   - Click the "+" button and use the Choose button to select a project
3. Select schemes from the automatically-detected list
4. Configure build arguments and options as needed
5. Click "Run Scan"
6. Results appear in Xcode format (text is selectable)

## Status

✅ **Completed** - Full GUI implementation is complete.

### Current Functionality

The app is fully functional with:
- Configuration persistence in UserDefaults
- Full Periphery integration via PeripheryScanRunner
- Automatic scheme detection from Xcode projects
- Drag-and-drop support for adding projects
- Scan execution with formatted results display
- macOS-native UI following Apple's layout guidelines

### Implemented Features
- Configuration management UI with multiple saved configurations
- File pickers and drag-and-drop for project selection
- Automatic scheme detection with checkboxes
- Settings persistence in UserDefaults
- Scan execution with results display
- Local modified Periphery package with git subtree management

### Potential Future Enhancements
- Improved results display with file locations and declaration details
- Filtering and search within results
- Export functionality to save results
- Detailed progress tracking during scans

## Code Organization

The codebase follows clear separation of concerns:
- **Views** - Separated into focused components (SidebarView, ConfigurationFormView, ConfigurationDetailView, etc.)
- **Configuration logic** - Isolated in ConfigurationManager with JSON persistence
- **Periphery integration** - Wrapped in PeripheryScanRunner with custom GUIShell
- **Helper utilities** - XcodeSchemeReader and SchemeCache provide supporting functionality
- **Shared utilities** - Located in `Utilities/` folder (e.g., `DeclarationIconHelper`, `TypeLabelFormatter`)

## Files Created

### Main Application Files

**Views (SwiftUI Components):**
- `TreeswiftApp.swift` - App entry point with window configuration
- `ContentView.swift` - Main coordinator view with NavigationSplitView
- `SidebarView.swift` - Sidebar with configuration list, +/- buttons, and drag-and-drop support
- `ConfigurationDetailView.swift` - Detail view showing configuration form and scan results
- `ConfigurationFormView.swift` - Form for editing configuration settings with macOS layout guidelines

**Configuration Management:**
- `PeripheryConfiguration.swift` - Codable struct with all Periphery configuration options
- `ConfigurationManager.swift` - ObservableObject managing configuration list with UserDefaults persistence
- `PeripheryConfiguration+Conversion.swift` - Extension to convert to Periphery's Configuration class

**Periphery Integration:**
- `PeripheryScanRunner.swift` - Main wrapper class with custom GUIShell for PATH handling
- `XcodeSchemeReader.swift` - Queries xcodebuild for available schemes in projects/workspaces
- `SchemeCache.swift` - In-memory cache for scheme queries (cleared on app deactivation)

### Project Configuration
- `Treeswift.xcodeproj/project.pbxproj` - References local Periphery package at `PeripherySource/periphery`
- `PeripherySource/periphery/Package.swift` - Modified to expose additional library products
- `PeripherySource/periphery/Sources/Frontend/Project.swift` - Made class and methods public
- `PeripherySource/periphery/Sources/Frontend/Scan.swift` - Made class and methods public

## Dependencies Used

### From Local Periphery Package
All imported as library products from `PeripherySource/periphery`:
- `Configuration` - Scan configuration
- `Logger` - Logging infrastructure
- `Shared` - Shell, SwiftVersion, PeripheryError, ProjectKind
- `SourceGraph` - Code graph representation
- `PeripheryKit` - ScanResult, ScanResultBuilder, output formatters
- `Extensions` - FilePath utilities, String extensions
- `Indexer` - IndexPipeline, SwiftIndexer, source file collection
- `ProjectDrivers` - XcodeProjectDriver, SPMProjectDriver, etc.
- `SyntaxAnalysis` - Swift syntax analysis
- `XcodeSupport` - Xcode project/workspace support
- `FrontendLib` - Project and Scan orchestration classes

### External Package Dependencies
Referenced by the local Periphery package:
- `XcodeProj` - Xcode project file parsing
- `SwiftSyntax` - Swift syntax tree analysis
- `Yams` - YAML parsing
- `SwiftIndexStore` - Index store reading
- `AEXML` - XML parsing for XIB/Storyboard files
- `swift-system` - System path utilities (FilePath)
- `swift-argument-parser` - Command-line argument parsing
- `swift-filename-matcher` - File pattern matching
