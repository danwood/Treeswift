# External Automation & Control Interface for Treeswift

## Goal

Enable an external agent (such as Claude Code) to programmatically control a running Treeswift instance: launch it, trigger scans, read results, perform code removal operations, and inspect outcomes. This turns Treeswift into a testable, automatable tool that Claude can use in a develop-test-verify loop.

## Use Cases

1. **Automated testing of Treeswift itself** -- After implementing a bugfix or feature in Treeswift, Claude launches the app, scans a real codebase (e.g., ProdCore), and verifies the output matches expectations.
2. **Code cleanup automation** -- Claude scans a project, reads the results tree, decides which items to clean up, executes removal, and verifies the target project still builds.
3. **Regression testing** -- Compare scan results before and after a Periphery change to detect regressions.

## Desired Operations

| # | Operation | Input | Output |
|---|-----------|-------|--------|
| 1 | Launch app | Port number (via CLI arg) | Confirmation that the app is ready |
| 2 | Select/create configuration | Project path, scheme, targets | Configuration ID |
| 3 | Start scan | Configuration ID | Scan started acknowledgment |
| 4 | Wait for scan completion | Configuration ID | Success/failure + summary stats |
| 5 | Read results tree | Configuration ID, tab name | Serialized tree (JSON) |
| 6 | Read detail for a node | Node ID | Node detail info (JSON) |
| 7 | Set viewing options | Option key/value pairs | Confirmation |
| 8 | Preview removal | Node ID(s), removal strategy | List of what would be deleted (JSON) |
| 9 | Execute removal | Node ID(s), removal strategy | Results summary (JSON) |
| 10 | Get app status | (none) | Current state (idle, scanning, etc.) |
| 11 | Quit app | (none) | Confirmation |

## Chosen IPC Mechanism: HTTP Server (localhost)

Run a lightweight HTTP server inside the app on a localhost port. This is the most practical approach for Claude integration:

- Claude can issue `curl` commands directly from Bash — no special tooling needed
- JSON request/response is natural for structured data
- REST endpoints map cleanly to the desired operations
- Raw text endpoints (e.g., scan logs) return `text/plain` and use a `/raw` path suffix to make this explicit
- Built-in HTTP status codes handle errors cleanly

**Transport details:**

- Opt-in via launch argument: `--automation-port <port>` (no default; the server only starts if this argument is provided)
- Port conflict: if the specified port is already in use, the server fails to start with a clear error message; no fallback to another port
- Port discovery: on launch, the server writes its port number to `/tmp/treeswift-control.port`; this file is cleaned up on graceful shutdown
- Localhost-only binding; no authentication required for the initial implementation
- A stale port file (app crashed) is detectable by attempting a connection

**Why not the alternatives:**

- **Unix domain socket (JSON-RPC):** Valid technically, but `curl` usage is simpler than socket tooling for the Claude use case
- **Custom URL scheme:** One-way only; no response channel
- **Apple Events / AppleScript:** Heavyweight; poor fit for SwiftUI apps
- **XPC Service:** Designed for app-to-helper, not external-to-app control; overkill

## HTTP Server Implementation

Use **Network.framework (`NWListener` + `NWConnection`)** with a minimal HTTP parser. This avoids external dependencies while leveraging Apple's modern networking API. HTTP parsing is handled using `CFHTTPMessage` from Core Foundation, which takes care of the parsing boilerplate without requiring a full web framework.

Swift NIO / Vapor would be overkill for this use case.

## Proposed API Design

All structured-data endpoints return `application/json`. Endpoints that return raw text (e.g., log output) return `text/plain` and include `/raw` in their path to make this unambiguous. Errors use standard HTTP status codes with a JSON error body: `{ "error": "description" }`.

### System

```
GET  /status                    -> { state: "idle"|"scanning"|..., version: "1.0" }
POST /quit                      -> { ok: true }
```

### Configurations

```
GET  /configurations            -> [{ id, name, projectPath, scheme, ... }]
GET  /configurations/:id        -> { id, name, projectPath, scheme, ... }
POST /configurations            -> Create a new configuration (body: JSON); returns { id, ... }
```

Configuration IDs are UUIDs assigned at creation time.

### Scanning

```
POST /configurations/:id/scan              -> Start a scan; returns { ok: true }
                                              Returns 409 Conflict if a scan is already running.
GET  /configurations/:id/scan/status       -> { isScanning, scanStatus, errorMessage }
GET  /configurations/:id/scan/wait         -> Long-poll: blocks until scan completes, then returns summary.
                                              No server-side timeout. If client disconnects, continuation
                                              is discarded but the scan continues unaffected.
GET  /configurations/:id/scan/log/raw      -> Raw text log output from the most recent scan (text/plain)
```

### Results

```
GET /configurations/:id/results/periphery-tree    -> Serialized tree JSON
GET /configurations/:id/results/categories/:name  -> Serialized category section JSON
GET /configurations/:id/results/files-tree         -> File browser tree JSON
GET /configurations/:id/results/summary            -> { totalResults, byKind: {...} }
```

All results endpoints return 404 with `{ "error": "no scan results available" }` if no scan has completed for the configuration.

### Code Operations

```
POST /configurations/:id/removal/preview
  Body: { nodeIds: [...], strategy: "skipReferenced"|"forceRemoveAll"|"cascade" }
  -> { itemsToDelete: [...], dependencyChains: [...] }

POST /configurations/:id/removal/execute
  Body: { nodeIds: [...], strategy: "skipReferenced"|"forceRemoveAll"|"cascade" }
  -> { deleted: [...], skipped: [...], errors: [...] }

GET /configurations/:id/removal/log/raw
  -> Raw text log from the most recent removal operation (text/plain)
```

### Viewing Options

```
GET  /configurations/:id/view-options        -> { showOnlyViews, selectedTab, ... }
POST /configurations/:id/view-options        -> Set options (body: JSON partial); returns { ok: true }
```

### Client Side (for Claude)

No special client is needed. Claude uses `curl` from Bash:

```bash
# Check if Treeswift is running and ready
curl -s http://localhost:21663/status

# List configurations
curl -s http://localhost:21663/configurations

# Start a scan
curl -s -X POST http://localhost:21663/configurations/SOME-UUID/scan

# Wait for scan to complete (long-poll)
curl -s http://localhost:21663/configurations/SOME-UUID/scan/wait

# Get the raw scan log
curl -s http://localhost:21663/configurations/SOME-UUID/scan/log/raw

# Get the periphery results tree
curl -s http://localhost:21663/configurations/SOME-UUID/results/periphery-tree

# Preview removal of a specific node
curl -s -X POST http://localhost:21663/configurations/SOME-UUID/removal/preview \
  -H "Content-Type: application/json" \
  -d '{"nodeIds": ["path/to/file.swift"], "strategy": "skipReferenced"}'

# Execute the removal
curl -s -X POST http://localhost:21663/configurations/SOME-UUID/removal/execute \
  -H "Content-Type: application/json" \
  -d '{"nodeIds": ["path/to/file.swift"], "strategy": "cascade"}'

# Get the raw removal log
curl -s http://localhost:21663/configurations/SOME-UUID/removal/log/raw
```

## Implementation Milestones

### Milestone 0: Source Tree Reorganization

**Goal:** Reorganize the existing source tree into three clear layers before adding new code, so the server has a clean home and the separation of concerns is explicit.

The current `Treeswift/` source folder gets reorganized into:

```
Treeswift/
  main.swift
  TreeswiftApp.swift

  Shared/                          ← pure helpers; no UI or server deps
    StringExtensions.swift
    URLExtensions.swift
    PathFormatter.swift
    PrintCapture.swift

  Core/                            ← back-end processing; used by both UI and AutomationServer
    Analysis/                      ← moved as-is (ConfigurationManager, ScanState, etc.)
    ProjectAccess/                 ← moved as-is (SchemeCache, XcodeSchemeReader, etc.)
    ResultsTree/                   ← moved as-is (TreeNode, FileNode+CodeRemoval, SwiftType)
    CLI/                           ← moved as-is (CLIScanRunner)
    Operations/                    ← code modification back-end (from Utilities/)
      CodeModificationError.swift
      CodeModificationHelper.swift
      CommentScanner.swift
      DeclarationDeletionHelper.swift
      DeclarationExtensions.swift
      FileChangeDetector.swift
      FileContentAnalyzer.swift
      FileDeletionHandler.swift
      FileOperations.swift
      ModificationLogger.swift
      ModificationOperation.swift
      PeripheryIgnoreCommentInserter.swift
      PeripheryKit-extensions.swift
      PreviewDetectionHelper.swift
      ProjectURLResolver.swift
      ScanResultIndex.swift
      SourceFileReader.swift
      SourceGraphLineAdjuster.swift
      UndoRedoHelper.swift
      UnusedDependencyAnalyzer.swift
      WarningStateManager.swift
    Utilities/                     ← domain utilities without UI deps (from Utilities/)
      EditorOpener.swift
      LaunchArgumentsHandler.swift
      SearchMatchEngine.swift
      TreeNodeFinder.swift
      TypeAheadState.swift

  UI/                              ← SwiftUI layer only
    (existing UI/ contents, unchanged)
    DisplayModels/                 ← renamed from TreeDisplayModels/
      CodeTreeModels.swift
      FilesTree/
        FileAnalysis.swift
        FileBrowserModels.swift
        FileTypeInfo.swift
        FolderAnalysis.swift
        Warnings.swift
    Helpers/                       ← UI-only helpers (from Utilities/)
      CopyableFocusedValue.swift
      EmojiRender.swift
      FocusableHostingView.swift
      LayoutConstants.swift
      NSColorExtensions.swift
      ScanResultHelper.swift
      SearchNavigationState.swift
      TreeCopyFormatter.swift
      TreeIcon.swift
      TreeKeyboardNavigation.swift
      WidthPreservingModifier.swift

  AutomationServer/                ← new; HTTP server (added in Milestone 1)
```

**Validation:** Project builds cleanly after the move. No code changes — only file/folder moves.

### Milestone 1: Embedded HTTP Server + Basic Status

**Goal:** Get the server running inside Treeswift and responding to basic queries.

- Create `AutomationServer` class using `NWListener` + `NWConnection` (Network.framework) with `CFHTTPMessage` for HTTP parsing
- Start/stop with app lifecycle (in `TreeswiftApp`), only when `--automation-port <port>` is provided
- Implement `GET /status` endpoint
- Implement `GET /configurations` endpoint (read-only list)
- Write port file to `/tmp/treeswift-control.port` on start, clean up on stop
- All server code lives in `AutomationServer/` (see Folder Structure below)

**Validation:** `curl http://localhost:21663/status` returns JSON from a running Treeswift instance.

### Milestone 2: Scan Control

**Goal:** Trigger and monitor scans externally.

- Implement `POST /configurations/:id/scan` (trigger scan)
- Implement `GET /configurations/:id/scan/status` (poll status)
- Implement `GET /configurations/:id/scan/wait` (long-poll until complete)
- Implement `GET /configurations/:id/scan/log/raw` (raw scan log text)
- Handle error cases (config not found, scan already running, scan failure)

**Validation:** Claude can start a scan on ProdCore and wait for it to finish; raw log is readable.

### Milestone 3: Results Reading

**Goal:** Read scan results in structured JSON form.

- Define `Codable` serialization for `TreeNode`, `FolderNode`, `FileNode`
- Define `Codable` serialization for `CategoriesNode` and its children
- Implement `GET /configurations/:id/results/periphery-tree`
- Implement `GET /configurations/:id/results/categories/:name`
- Implement `GET /configurations/:id/results/summary`
- Include relevant metadata per node (warning kind, line numbers, declaration info)

**Validation:** Claude can read the full results tree and parse it. Primary use case is remote debugging of scan and repair operations.

### Milestone 4: Code Removal Operations

**Goal:** Preview and execute code removal operations externally.

- Implement `POST /configurations/:id/removal/preview`
- Implement `POST /configurations/:id/removal/execute`
- Implement `GET /configurations/:id/removal/log/raw`
- Wire into existing `DeclarationDeletionHelper` / removal infrastructure
- Return structured results (what was deleted, what was skipped, any errors)

**Validation:** Claude can remove unused code from a file and get confirmation of what changed; raw removal log is accessible.

### Milestone 5: Configuration Creation & View Options

**Goal:** Full control over viewing options and configuration creation.

- Implement `POST /configurations` (create a new configuration)
- Implement view options read/write endpoints
- Implement `POST /quit`

**Validation:** Claude can create a configuration for a new project, scan it, and read results without any manual GUI interaction.

### Milestone 6: Results Detail & Files Tree

**Goal:** Complete the results API.

- Implement `GET /configurations/:id/results/files-tree`
- Implement `GET /configurations/:id/results/categories/:name`

**Validation:** Claude can navigate the full results tree by category and file.

### Milestone 7: Polish & Robustness

**Goal:** Production-quality automation interface.

- Add request logging (for debugging)
- Handle edge cases (concurrent requests, app quitting during a request, etc.)
- Document the full API in a markdown file
- Consider adding a small health-check/keepalive mechanism

## Folder Structure

All server-side code lives in a top-level `AutomationServer/` folder. This keeps it cleanly separated from UI code and makes it easy to extract into a Swift package later.

```
AutomationServer/
  AutomationServer.swift        // NWListener setup, lifecycle, port file management
  HTTPConnection.swift          // Per-connection handler (NWConnection + CFHTTPMessage parsing)
  Router.swift                  // Route matching and dispatch
  Handlers/
    StatusHandler.swift
    ConfigurationsHandler.swift
    ScanHandler.swift
    ResultsHandler.swift
    RemovalHandler.swift
    ViewOptionsHandler.swift
```

Handlers interact with `@MainActor`-isolated app state (e.g., `ConfigurationManager`, `ScanStateManager`) by dispatching to `MainActor`. The server itself runs on a background queue.

## Technical Considerations

### Concurrency Model

- The HTTP server listens on a background thread/queue (Network.framework dispatches on its own queue)
- All handlers that touch app state dispatch to `@MainActor`
- Long-poll endpoints (`/scan/wait`) use Swift concurrency (`withCheckedContinuation`) to suspend until the scan completes, then resume with the response
- The server handles multiple concurrent connections (e.g., status checks while a long-poll is waiting)

### JSON Serialization

- `TreeNode`, `FolderNode`, `FileNode` should get `Codable` conformance (or we define separate API response types that mirror them)
- Periphery's `ScanResult` and `Declaration` types may need wrapper types for clean JSON output
- Use `JSONEncoder` with `.sortedKeys` for deterministic output

### Lifecycle Management

- Server starts when the app launches only if `--automation-port <port>` is provided
- Server stops on app termination; port file is deleted on graceful shutdown
- If the app crashes, the stale port file is detectable by attempting a connection and getting a connection refused

### Raw Text Endpoints

Endpoints with `/raw` in the path return `Content-Type: text/plain`. These are used for log output that is inherently unstructured. The naming convention makes it unambiguous in the URL that the response is not JSON. Only the most recent operation's log is retained; a second scan overwrites the first log. A request before any operation has run returns a 404.

## WebSocket Support (Future Consideration — Not Scheduled)

Long-polling (`/scan/wait`) is sufficient for the Claude automation use case, but a WebSocket channel could provide real-time progress updates without a dedicated polling loop. This would be most useful if:

- Scan progress events (percentage complete, current file being analyzed) need to stream to the client in real time
- Multiple clients want to observe the same scan concurrently
- The client needs to receive push notifications for state changes (scan started by the GUI, for example)

A possible design: the server upgrades a connection to WebSocket on `GET /events`, then pushes JSON event objects as they occur:

```json
{ "event": "scanStarted", "configId": "...", "timestamp": "..." }
{ "event": "scanProgress", "configId": "...", "percent": 42 }
{ "event": "scanCompleted", "configId": "...", "summary": { ... } }
{ "event": "removalExecuted", "configId": "...", "deleted": [...] }
```

This would require either adding WebSocket framing support on top of `NWConnection`, or pulling in a lightweight dependency. Given that long-polling is adequate for the primary use case, this is deferred.

