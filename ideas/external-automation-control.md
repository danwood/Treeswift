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
| 1 | Launch app | (none or config name) | Confirmation that the app is ready |
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

## IPC Mechanism Evaluation

### Option A: Unix Domain Socket with JSON-RPC

A lightweight TCP-like server running inside the app, listening on a Unix domain socket (e.g., `/tmp/treeswift-control.sock`). Commands are JSON-RPC 2.0 messages; responses are JSON.

**Pros:**
- Simple request/response model maps directly to our use cases
- Claude can interact via simple socket reads/writes (e.g., `socat` or a small Swift CLI)
- No macOS framework dependencies; works in any sandbox configuration
- Bidirectional: can support async notifications (scan progress) via JSON-RPC notifications
- Easy to test with `curl --unix-socket` or `nc -U`
- Fast, low-overhead, no serialization beyond JSON

**Cons:**
- Need to implement the socket server (though Foundation's `NWListener` makes this straightforward)
- Need to handle connection lifecycle, error recovery
- Socket file cleanup on crash

### Option B: Custom URL Scheme

Register a URL scheme (e.g., `treeswift://`) and use `onOpenURL` to handle commands.

**Pros:**
- Native macOS pattern; trivial to invoke via `open -g treeswift://scan?config=ProdCore`
- Automatically launches the app if not running

**Cons:**
- One-way only: no response channel. The caller cannot get results back.
- Complex operations (read results, preview removal) don't fit the URL model
- Requires polling or a separate channel for results
- Query string encoding is fragile for complex parameters

**Verdict:** Not suitable as the primary mechanism. Could be useful as a supplementary "launch and trigger" mechanism.

### Option C: Apple Events / AppleScript

Expose a scripting dictionary (`.sdef`) and respond to Apple Events.

**Pros:**
- Classic macOS automation pattern
- `osascript` is available everywhere
- Can return values

**Cons:**
- Heavyweight: requires defining an `.sdef` file, Apple Event handlers, Cocoa Scripting support
- Poor fit for SwiftUI apps (Cocoa Scripting expects an NSDocument-based architecture)
- Clunky for complex structured data (arrays of trees)
- Debugging is painful; error messages are cryptic
- AppleScript syntax is awkward for programmatic use

**Verdict:** Too heavyweight and architecturally mismatched for a SwiftUI app.

### Option D: XPC Service

Create an XPC service that the app hosts; external tools connect to it.

**Pros:**
- Apple's recommended IPC mechanism
- Strong typing via NSXPCInterface/Codable

**Cons:**
- Designed for app-to-helper communication, not external-to-app control
- Requires the external tool to know the XPC service name and have proper entitlements
- Complex setup: separate target, interface protocol, connection management
- Overkill for our use case

**Verdict:** Wrong tool for this job.

### Option E: HTTP Server (localhost)

Run a lightweight HTTP server inside the app on a localhost port.

**Pros:**
- Universal client support (`curl`, any HTTP library)
- REST API is well-understood
- Can serve JSON responses directly
- Claude can use `curl` commands trivially

**Cons:**
- Port conflicts (need to pick/discover a port)
- Slightly heavier than a Unix socket
- Security consideration: any local process can connect (mitigated by localhost-only binding + optional token)

**Pros over Unix socket:**
- Easier for Claude to use (`curl http://localhost:PORT/...` vs socket tooling)
- Built-in HTTP semantics (status codes, content types)
- Can potentially add a simple web UI for debugging

**Verdict:** Strong candidate. Very practical for the Claude use case.

### Recommendation: **Option E (HTTP Server)** as primary, with **Option A (Unix Socket)** as an alternative

The HTTP server approach is the most practical for Claude integration:
- Claude can issue `curl` commands directly from Bash
- JSON request/response is natural
- REST endpoints map cleanly to our operations
- No special tooling needed on the client side
- Foundation's `NWListener` or a lightweight embedded server (e.g., using `HTTPServer` from Swift NIO, or even a simple `NWListener` with HTTP parsing) can handle this

However, a Unix domain socket with JSON-RPC is a solid fallback if HTTP adds unwanted complexity or if port management becomes an issue. The two approaches share the same JSON protocol; only the transport differs.

## Proposed Architecture

### Transport Layer

An embedded HTTP server running on `localhost` with a configurable port (default: a fixed port like `21663`, or written to a known file like `/tmp/treeswift-control.port`).

**Port discovery:** On launch, the server writes its port to `/tmp/treeswift-control.port`. The external agent reads this file to know where to connect. The file is cleaned up on graceful shutdown.

**Authentication:** Optional bearer token written to `/tmp/treeswift-control.token` to prevent other local processes from issuing commands. For initial implementation, this can be skipped (localhost-only is sufficient for dev use).

### Server Component (inside Treeswift)

```
AutomationServer (new)
  - Starts/stops with the app lifecycle
  - Listens on localhost:PORT
  - Parses HTTP requests, routes to handler methods
  - Handler methods interact with existing app state:
      - ConfigurationManager (read/write configurations)
      - ScanStateManager (trigger scans, read state)
      - ScanState (read results, trigger operations)
  - Serializes responses as JSON
```

The server runs on a background thread but dispatches all state access to `@MainActor` (since all the app's state objects are `@MainActor`).

### API Design

All endpoints return JSON. Errors use standard HTTP status codes with a JSON error body.

#### System

```
GET  /status                    -> { state: "idle"|"scanning"|..., version: "1.0" }
POST /quit                      -> { ok: true }
```

#### Configurations

```
GET  /configurations            -> [{ id, name, projectPath, scheme, ... }]
GET  /configurations/:id        -> { id, name, projectPath, scheme, ... }
POST /configurations            -> Create a new configuration (body: JSON)
```

#### Scanning

```
POST /configurations/:id/scan          -> Start a scan; returns { ok: true }
GET  /configurations/:id/scan/status   -> { isScanning, scanStatus, errorMessage }
GET  /configurations/:id/scan/wait     -> Long-poll: blocks until scan completes, then returns results summary
```

#### Results

```
GET /configurations/:id/results/periphery-tree    -> Serialized tree JSON
GET /configurations/:id/results/categories/:name  -> Serialized category section JSON
GET /configurations/:id/results/files-tree         -> File browser tree JSON
GET /configurations/:id/results/summary            -> { totalResults, byKind: {...} }
```

#### Code Operations

```
POST /configurations/:id/removal/preview
  Body: { nodeIds: [...], strategy: "skipReferenced"|"forceRemoveAll"|"cascade" }
  -> { itemsToDelete: [...], dependencyChains: [...] }

POST /configurations/:id/removal/execute
  Body: { nodeIds: [...], strategy: "skipReferenced"|"forceRemoveAll"|"cascade" }
  -> { deleted: [...], skipped: [...], errors: [...] }
```

#### Viewing Options

```
GET  /configurations/:id/view-options        -> { showOnlyViews, selectedTab, ... }
POST /configurations/:id/view-options        -> Set options (body: JSON partial)
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
```

## Implementation Milestones

### Milestone 1: Embedded HTTP Server + Basic Status

**Goal:** Get the server running inside Treeswift and responding to basic queries.

- Create `AutomationServer` class using `NWListener` (Network framework) or a simple `HTTPServer` implementation
- Start/stop with app lifecycle (in `TreeswiftApp`)
- Implement `GET /status` endpoint
- Implement `GET /configurations` endpoint (read-only list)
- Write port file to `/tmp/treeswift-control.port` on start, clean up on stop
- Add a preference or launch argument (`--automation-port <port>`) to enable/configure

**Validation:** `curl http://localhost:21663/status` returns JSON from a running Treeswift instance.

### Milestone 2: Scan Control

**Goal:** Trigger and monitor scans externally.

- Implement `POST /configurations/:id/scan` (trigger scan)
- Implement `GET /configurations/:id/scan/status` (poll status)
- Implement `GET /configurations/:id/scan/wait` (long-poll until complete)
- Handle error cases (config not found, scan already running, scan failure)

**Validation:** Claude can start a scan on ProdCore and wait for it to finish.

### Milestone 3: Results Reading

**Goal:** Read scan results in structured JSON form.

- Define `Codable` serialization for `TreeNode`, `FolderNode`, `FileNode`
- Define `Codable` serialization for `CategoriesNode` and its children
- Implement `GET /configurations/:id/results/periphery-tree`
- Implement `GET /configurations/:id/results/categories/:name`
- Implement `GET /configurations/:id/results/summary`
- Include relevant metadata per node (warning kind, line numbers, declaration info)

**Validation:** Claude can read the full results tree and parse it.

### Milestone 4: Code Removal Operations

**Goal:** Preview and execute code removal operations externally.

- Implement `POST /configurations/:id/removal/preview`
- Implement `POST /configurations/:id/removal/execute`
- Wire into existing `DeclarationDeletionHelper` / removal infrastructure
- Return structured results (what was deleted, what was skipped, any errors)

**Validation:** Claude can remove unused code from a file and get confirmation of what changed.

### Milestone 5: View Options & Configuration Management

**Goal:** Full control over viewing options and configuration creation.

- Implement view options read/write endpoints
- Implement configuration creation endpoint
- Implement `POST /quit`

**Validation:** Claude can create a configuration for a new project, scan it, and read results without any manual GUI interaction.

### Milestone 6: Polish & Robustness

**Goal:** Production-quality automation interface.

- Add optional bearer token authentication
- Add request logging (for debugging)
- Handle edge cases (concurrent requests, app quitting during a request, etc.)
- Add a `GET /configurations/:id/results/files-tree` endpoint
- Document the full API in a markdown file
- Consider adding a small health-check/keepalive mechanism

## Technical Considerations

### HTTP Server Implementation

The simplest approach for a macOS app (no external dependencies):

1. **Network.framework (`NWListener`)** -- Apple's modern networking API. Can listen on a TCP port. We'd need to parse HTTP ourselves (straightforward for a simple REST API). Advantages: no external dependencies, modern async-friendly API.

2. **GCDAsyncSocket or raw BSD sockets** -- Lower-level, more boilerplate.

3. **Swift NIO / Vapor** -- Full-featured but adds a heavyweight dependency. Probably overkill.

4. **`python3 -m http.server` style approach (separate process)** -- Defeats the purpose; we need in-process access to app state.

**Recommendation:** Use Network.framework (`NWListener` + `NWConnection`) with a minimal HTTP parser. The API surface is small enough that we don't need a full web framework. Alternatively, use `CFHTTPMessage` for HTTP parsing (it's available in Core Foundation and handles the parsing boilerplate).

### Concurrency Model

- The HTTP server listens on a background thread/queue
- All handlers that touch app state dispatch to `@MainActor`
- Long-poll endpoints (`/scan/wait`) use Swift concurrency (`withCheckedContinuation`) to suspend until the scan completes, then resume with the response
- The server should handle multiple concurrent connections (e.g., status checks while a long-poll is waiting)

### JSON Serialization

- `TreeNode`, `FolderNode`, `FileNode` should get `Codable` conformance (or we define separate API response types that mirror them)
- Periphery's `ScanResult` and `Declaration` types may need wrapper types for clean JSON output
- Use `JSONEncoder` with `.sortedKeys` for deterministic output

### Lifecycle Management

- Server starts when the app launches (if automation is enabled)
- Server stops on app termination
- Port file is written on start, deleted on stop
- If the app crashes, the stale port file is detected by checking if the port is actually responding

## Alternatives Considered but Rejected

- **Headless mode (no GUI):** Would require significant refactoring to decouple scan logic from SwiftUI state. The HTTP server approach lets us keep the GUI and control it externally, which also allows visual verification.
- **Scripting bridge / JXA:** Same issues as AppleScript -- poor fit for SwiftUI apps.
- **File-based IPC (write commands to a file, poll for results):** Fragile, slow, hard to synchronize. The HTTP approach is strictly better.
- **Distributed notifications:** One-way, no response channel, limited payload size.

## Open Questions

1. **Should automation be always-on or opt-in?** Leaning toward opt-in via a launch argument (`--enable-automation`) or preference, with the port file serving as the discovery mechanism.

2. **Should we support creating configurations via the API?** Or require them to be pre-created in the GUI? Creating via API is more useful for full automation but adds complexity.

3. **How much of the results tree detail do we need to serialize?** The full tree with all declaration metadata, or a summary? Probably need both: a summary endpoint for quick checks and a detailed endpoint for full inspection.

4. **Should the HTTP server be a separate Swift package/module?** This would keep it cleanly separated from the UI code. Could be a local package within the project.

5. **Do we need WebSocket support for real-time progress updates?** Or is polling/long-polling sufficient? For the Claude use case, long-polling is probably fine.
