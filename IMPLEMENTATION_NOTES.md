# Treeswift - Implementation Notes

## Overview

Treeswift is a macOS SwiftUI application providing a graphical interface for the Periphery static analysis tool. It runs Periphery scans directly in-process (no shell subprocess), displays results in multiple views, and supports code removal operations. It also includes an embedded HTTP server for external automation.

**For project-specific coding guidelines and constraints**, see [CLAUDE.md](CLAUDE.md).

---

## Source Tree Layout

All application source lives under `Treeswift/`, organized into four layers:

```
Treeswift/
  Shared/               Pure Swift helpers — no UI or server dependencies
                          StringExtensions, URLExtensions, PathFormatter, PrintCapture

  Core/
    Analysis/           Scan state, configuration management, Periphery runner
                          ConfigurationManager, ScanState, ScanStateManager,
                          PeripheryScanRunner, ScanResultCodable, ...
    CLI/                Command-line interface (--list, --scan)
    Operations/         Code modification helpers (deletion, ignore-comment insertion,
                          file operations, undo/redo, ...)
    ProjectAccess/      Xcode scheme detection, project URL resolution
    ResultsTree/        Tree model types (TreeNode, CategoriesNode, FileBrowserNode, ...)
    Utilities/          Back-end utilities (search, type-ahead, launch args, ...)

  UI/
    Components/         Reusable UI components
    DisplayModels/      CodeTreeModels + FilesTree display models
    Helpers/            UI-only helpers (icons, keyboard nav, copy formatter, ...)
    ResultsTabView/     Main results area (PeripheryTreeView, SingleCategoryTabView, ...)
    ResultsTreeView/    Results tree display
    ToolbarSearch/      Search bar
    UniversalDetailView/ Right-panel detail view
    ContentView.swift   Main coordinator (NavigationSplitView)
    SidebarView.swift

  AutomationServer/
    AutomationServer.swift   NWListener lifecycle, watcher task registry
    HTTPConnection.swift     Per-connection HTTP parser and response writer
    Router.swift             Request routing dispatch table
    Handlers/
      StatusHandler.swift
      ConfigurationsHandler.swift
      ScanHandler.swift
      ResultsHandler.swift
      RemovalHandler.swift
      ViewOptionsHandler.swift

  TreeswiftApp.swift    App entry point; owns all shared state
  main.swift            Bootstraps app or CLI based on launch arguments
```

---

## Local Periphery Package

`PeripherySource/periphery/` contains a complete copy of the Periphery source code, managed as a **git subtree** tracking the upstream repository. It is referenced as a **local Swift package** in the Xcode project.

The local package has been modified to:
- Expose additional library products (`Configuration`, `SourceGraph`, `FrontendLib`, etc.)
- Make internal classes public where needed (`Project`, `Scan`)
- Add location range tracking (endLine/endColumn properties)
- Add scan progress delegation for GUI feedback
- Support Swift 6 concurrency with cancellation checkpoints

**For complete details** on modifications, diff minimization strategy, and git subtree workflow, see [PeripherySource/periphery/README_Treeswift.md](PeripherySource/periphery/README_Treeswift.md).

---

## Technical Environment

- **Swift 6.2**, macOS 15.6+ deployment target
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — every type gets `@MainActor` by default; types that must be `nonisolated` (network handlers, router) require explicit annotation
- No App Sandbox — required for unrestricted file system access and `xcodebuild` invocation
- Blue folder references (PBXFileSystemSynchronizedRootGroup) — Xcode discovers source files by scanning the filesystem; no need to update the project file when reorganizing source

---

## Architecture

### State Ownership

All shared state is owned by `TreeswiftApp` and injected via `.environment(...)`:

| Type | Role |
|------|------|
| `ConfigurationManager` | Manages list of `PeripheryConfiguration` values; persists to UserDefaults |
| `ScanStateManager` | Vends per-configuration `ScanState` instances |
| `ScanState` | Holds current scan status, results, log buffers, file tree for one configuration |
| `FilterState` | View filter toggles (show/hide warning types, declaration kinds) |

`ContentView` and its subviews receive these via `@Environment`. The automation server also holds direct references.

### Scan Flow

```
TreeswiftApp
  → AutomationServer (holds references to ConfigurationManager, ScanStateManager, FilterState)
  → ContentView (receives state via @Environment)
      → ScanStateManager.getState(for: configId) → ScanState
          → ScanState.startScan(configuration:)
              → PeripheryScanRunner (async, runs Periphery in-process)
                  → populates treeNodes, categoryNodes, fileTreeNodes, scanResults
```

### Automation Server

The automation server is an embedded HTTP server using Apple's Network.framework (`NWListener`/`NWConnection`). It runs on a background `DispatchQueue`. All access to `@MainActor` state goes through `await MainActor.run {}`.

**Components:**

- **`AutomationServer`** (`@MainActor`) — creates and owns `NWListener`; manages a registry of active long-poll watcher tasks so `stop()` can cancel them all; writes the active port to `/tmp/treeswift-control.port`; detects stale port files on startup
- **`HTTPConnection`** (explicitly `nonisolated`) — one instance per TCP connection; accumulates data, manually parses HTTP headers and body (Content-Length framing), dispatches to `Router` via `Task.detached`, writes response
- **`Router`** (nonisolated struct) — pattern-matches `(method, pathComponents)` tuples; delegates to handler enums
- **Handlers** (nonisolated enums) — each handler resolves the config ID, accesses `@MainActor` state via `MainActor.run`, builds a `Codable` response value, returns `Router.Response`

**Concurrency notes:**

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` causes nested structs/enums to become `@MainActor` unless explicitly marked `nonisolated`. `HTTPConnection`, `Router`, all handlers, and all Codable response types are `nonisolated`.
- `Task.detached` is used in `HTTPConnection` to escape the `@MainActor` default when dispatching to the router.
- Long-poll (`/scan/wait`) creates an inner polling `Task`, registers it with `AutomationServer.addWatcherTask()`, and waits via `withTaskCancellationHandler`. `stop()` cancels all registered tasks.

**Port file lifecycle:**
1. On `start()`, check `/tmp/treeswift-control.port`; if the stored port matches and a server responds there, exit with error. Otherwise remove the stale file.
2. On `ready`, write current port to the file.
3. On `stop()`, delete the file.

---

## Key Design Decisions

**Local package approach:** Uses a local modified Swift package instead of adding files to the app target. Preserves module boundaries, allows clean `import PeripheryKit` etc., and makes `git subtree pull` upgrades straightforward.

**`@Observable` throughout:** `ConfigurationManager`, `ScanStateManager`, `ScanState`, and `FilterState` all use the `@Observable` macro. `TreeswiftApp` stores them as `@State`; `ContentView` and other views use plain properties (no `@ObservedObject`/`@StateObject`).

**Codable response wrappers:** `ScanResultCodable.swift` defines parallel `Codable Sendable` structs (`TreeNodeResponse`, `CategoriesNodeResponse`, `FileBrowserNodeResponse`, `ScanSummaryResponse`) that mirror the UI model types. These are separate so the UI models don't need to conform to `Codable`.

**Self-retain in HTTPConnection:** `HTTPConnection` holds `private var selfRetain: HTTPConnection?`. `start()` assigns `selfRetain = self`; the completion handler of `connection.send(...)` sets `selfRetain = nil`. This prevents the instance from being deallocated while the connection is open.

**`Binding<FilterState>` workaround:** `FilterState` is an `@Observable` reference type owned by `TreeswiftApp`. Views that need a `Binding<FilterState>` (e.g., for sheet presentation) use `Binding(get: { filterState }, set: { _ in })` — mutations go through the reference directly, so the no-op setter is correct.

---

## Automated Testing and Automation Server

### Launching Treeswift for Automation

Treeswift must be launched via `open` (not by directly executing the binary), as macOS apps launched from the terminal without proper bundle activation may fail to initialize their app delegate and will not start the automation server. Use:

```bash
open /path/to/Treeswift.app --args --automation-port 21663
```

Then poll until the server responds:

```bash
for i in $(seq 1 20); do
  result=$(curl -s "http://[::1]:21663/status" 2>/dev/null)
  if [ -n "$result" ]; then echo "up: $result"; break; fi
  sleep 2
done
```

The automation server binds to IPv6 loopback (`[::1]`), not `localhost` or `127.0.0.1`.

### Periphery Indexstore and Scan Accuracy

Periphery uses its **own DerivedData path** (under `~/Library/Caches/periphery/`) when scanning, separate from Xcode's standard `~/Library/Developer/Xcode/DerivedData/`. It passes `-derivedDataPath` to `xcodebuild` during the scan, so:

- Running `xcodebuild build` manually does **not** update the indexstore Periphery reads
- Only triggering a scan through Treeswift (or directly via Periphery CLI) will update the indexstore it uses
- The indexstore contains source positions (line/column numbers) for every declaration; stale positions cause code modifications to target wrong lines

**Critical rule:** always trigger a fresh scan (do not use `--skip-scan`) after any code changes to the target project, even if they were subsequently reverted with `git reset`. The scan cache records `cachedAt` timestamps but does not detect source changes; it is valid only for the exact source state at scan time.

**Symptom of stale scan cache:** access-control keyword insertions (`private`, `fileprivate`) land on wrong lines (closing braces, blank lines, comment lines) rather than declaration lines. Deletion operations may silently remove the wrong code.

### Integration Test Script (`scripts/integration-test-removal.sh`)

The test script tests `skipReferenced`, `forceRemoveAll`, and `cascade` removal strategies across all top-level folders in a target project. Key flags:

- `--skip-launch` — assume Treeswift is already running
- `--skip-scan` — reuse existing cached scan (only safe if source hasn't changed since last scan)
- `--skip-build` — skip the pre-scan index build (use only if indexstore is known current)
- `--folder NAME` — test only one folder
- `--reset-cache` — clear the results cache to re-run all combinations

**Do not use `--skip-scan` across test runs that modify and restore source**, as the scan cache will have stale positions.

---

## SwiftFormat Pre-Commit Hook Caveat

The project uses a `git-format-staged` pre-commit hook running SwiftFormat in stdin mode. When SwiftFormat fails to parse a file (e.g., files importing non-standard modules like `PeripheryKit`, `SourceGraph`), it may silently emit only the file header, causing the staged version to be truncated.

**After every commit involving automation server handler files, verify line counts:**

```bash
git show HEAD:Treeswift/AutomationServer/Handlers/RemovalHandler.swift | wc -l
# Should be well over 50 lines; if it's ≤ 25, the file was truncated
```

If truncated, restore with `git checkout HEAD -- <path>` then rewrite the file outside of a commit.

---

## Supported Project Types

All Periphery-supported project types work:
- ✅ Xcode projects (.xcodeproj, .xcworkspace)
- ✅ SPM (Swift Package Manager) projects
- ✅ Bazel projects
- ✅ Generic projects (with custom configuration)

---

## Dependencies

### From Local Periphery Package

- `Configuration` — scan configuration
- `Logger` — logging infrastructure
- `Shared` — Shell, SwiftVersion, PeripheryError, ProjectKind
- `SourceGraph` — code graph representation
- `PeripheryKit` — ScanResult, ScanResultBuilder, output formatters
- `Extensions` — FilePath utilities, String extensions
- `Indexer` — IndexPipeline, SwiftIndexer, source file collection
- `ProjectDrivers` — XcodeProjectDriver, SPMProjectDriver, etc.
- `SyntaxAnalysis` — Swift syntax analysis
- `XcodeSupport` — Xcode project/workspace support
- `FrontendLib` — Project and Scan orchestration classes

### External Package Dependencies (via Periphery)

- `XcodeProj` — Xcode project file parsing
- `SwiftSyntax` — Swift syntax tree analysis
- `Yams` — YAML parsing
- `SwiftIndexStore` — index store reading
- `AEXML` — XML parsing for XIB/Storyboard files
- `swift-system` — system path utilities (FilePath)
- `swift-argument-parser` — command-line argument parsing
- `swift-filename-matcher` — file pattern matching
