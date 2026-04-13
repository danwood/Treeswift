# Treeswift Automation API

Treeswift includes an embedded HTTP server for external control. Launch with `--automation-port <port>` to enable it.

```bash
open Treeswift.app --args --automation-port 21663
```

The server writes the active port to `/tmp/treeswift-control.port` when ready.

All endpoints are on `http://localhost:<port>/`. All responses are JSON unless noted.

---

## General

### GET /status

Returns current server state.

```bash
curl http://localhost:21663/status
```

Response:
```json
{"state": "idle", "version": "1.0"}
```

`state` is `"idle"` or `"scanning"`.

---

### POST /quit

Terminates the application.

```bash
curl -X POST http://localhost:21663/quit
```

---

## Configurations

### GET /configurations

Returns all configurations.

```bash
curl http://localhost:21663/configurations
```

### GET /configurations/:id

Returns a single configuration by UUID.

```bash
curl http://localhost:21663/configurations/782B1ACE-4832-4826-8FCE-0021F5114808
```

### POST /configurations

Creates a new configuration. The `id` field is optional — a UUID is assigned if absent.

```bash
curl -X POST http://localhost:21663/configurations \
  -H "Content-Type: application/json" \
  -d '{"name":"My Project","projectType":"xcode","project":"/path/to/MyApp.xcodeproj","schemes":["MyApp"]}'
```

Returns the created configuration with status 201.

---

## Scan Control

All scan endpoints require a configuration `:id` (UUID string).

### POST /configurations/:id/scan

Starts a scan. Returns 409 if a scan is already running.

```bash
curl -X POST http://localhost:21663/configurations/$ID/scan
# {"ok": true}
```

### GET /configurations/:id/scan/status

Returns current scan state.

```bash
curl http://localhost:21663/configurations/$ID/scan/status
# {"isScanning": true, "scanStatus": "Analyzing…", "errorMessage": null}
```

### GET /configurations/:id/scan/wait

Long-polls until the scan completes, then returns final scan status. Use `--max-time` to set a client-side timeout.

```bash
curl --max-time 300 http://localhost:21663/configurations/$ID/scan/wait
# {"isScanning": false, "scanStatus": "Scan complete", "errorMessage": null}
```

### GET /configurations/:id/scan/log/raw

Returns buffered scan log lines as plain text. Returns 404 if no log is available yet.

```bash
curl http://localhost:21663/configurations/$ID/scan/log/raw
```

---

## Results

All results endpoints return 404 if no scan has been run yet.

### GET /configurations/:id/results/summary

Returns total warning count grouped by annotation type.

```bash
curl http://localhost:21663/configurations/$ID/results/summary
# {"totalCount": 129, "byAnnotation": {"unused": 76, "assignOnlyProperty": 39, ...}}
```

### GET /configurations/:id/results/periphery-tree

Returns the full Periphery results tree (folder/file hierarchy with warnings).

```bash
curl http://localhost:21663/configurations/$ID/results/periphery-tree
```

Each node has: `id`, `type` (`"folder"` or `"file"`), `name`, `path`, `children` (folders only).

### GET /configurations/:id/results/categories/:name

Returns a specific categories section. Valid names:

| Name | Description |
|------|-------------|
| `tree` | Hierarchy section |
| `viewExtensions` | View extensions |
| `shared` | Shared types |
| `orphans` | Orphaned types |
| `previewOrphans` | Preview orphans |
| `bodyGetter` | Body getter only |
| `unattached` | Unattached declarations |

```bash
curl http://localhost:21663/configurations/$ID/results/categories/orphans
```

Each node has: `id`, `type` (`"section"`, `"declaration"`, or `"syntheticRoot"`), `displayName`, `filePath`, `line`, `isView`, `relationship`, `conformances`, `children`.

### GET /configurations/:id/results/files-tree

Returns the file browser tree enriched with type analysis and usage badges.

```bash
curl http://localhost:21663/configurations/$ID/results/files-tree
```

Each node has: `id`, `type` (`"directory"` or `"file"`), `name`, `path` (files only), `containsSwiftFiles` (directories only), `usageBadge` (files only, e.g. `"3 unused (warning)"`), `children` (directories only).

---

## Code Removal

### POST /configurations/:id/removal/preview

Computes what would be removed without writing any files.

```bash
curl -X POST http://localhost:21663/configurations/$ID/removal/preview \
  -H "Content-Type: application/json" \
  -d '{}'
```

Request body (all optional):
- `nodeIds`: array of node IDs from periphery-tree to target (omit for all files)
- `strategy`: `"forceRemoveAll"` (default), `"skipReferenced"`, or `"cascade"`

Response:
```json
{
  "files": [{"filePath": "...", "deletableCount": 3, "nonDeletableCount": 1, "wouldDeleteFile": false}],
  "totalDeletable": 93,
  "totalNonDeletable": 9
}
```

### POST /configurations/:id/removal/execute

Executes removal and writes changes to disk. **Modifies source files.**

```bash
curl -X POST http://localhost:21663/configurations/$ID/removal/execute \
  -H "Content-Type: application/json" \
  -d '{"nodeIds": ["/path/to/File.swift"], "strategy": "skipReferenced"}'
```

Response:
```json
{
  "files": [{"filePath": "...", "deletedCount": 3, "nonDeletableCount": 1, "deleted": false}],
  "totalDeleted": 93,
  "errors": []
}
```

### GET /configurations/:id/removal/log/raw

Returns the removal operation log as plain text. Returns 404 if no removal has been run.

```bash
curl http://localhost:21663/configurations/$ID/removal/log/raw
```

---

## View Options

View options control which warnings are shown in the UI. These correspond to the FilterState.

### GET /configurations/:id/view-options

Returns current filter settings.

```bash
curl http://localhost:21663/configurations/$ID/view-options
```

### POST /configurations/:id/view-options

Updates one or more filter settings. All fields are optional; only provided fields are changed.

```bash
curl -X POST http://localhost:21663/configurations/$ID/view-options \
  -H "Content-Type: application/json" \
  -d '{"topLevelOnly": false, "showUnused": true}'
```

Available boolean fields: `topLevelOnly`, `showUnused`, `showAssignOnly`, `showRedundantProtocol`, `showRedundantAccessControl`, `showSuperfluousIgnoreCommand`, `showClass`, `showEnum`, `showExtension`, `showFunction`, `showImport`, `showInitializer`, `showParameter`, `showProperty`, `showProtocol`, `showStruct`, `showTypealias`.

---

## Typical Workflow

```bash
BASE="http://localhost:21663"

# Get first configuration ID
ID=$(curl -s $BASE/configurations | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

# Start a scan and wait for it to finish
curl -s -X POST $BASE/configurations/$ID/scan
curl -s --max-time 300 $BASE/configurations/$ID/scan/wait

# Check what would be removed
curl -s -X POST $BASE/configurations/$ID/removal/preview \
  -H "Content-Type: application/json" -d '{}'

# View results summary
curl -s $BASE/configurations/$ID/results/summary
```
