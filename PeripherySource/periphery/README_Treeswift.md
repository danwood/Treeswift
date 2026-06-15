# Treeswift Modifications to Periphery

> **Concern B — Periphery library-integration glue only.** This file documents the changes that make
> Periphery importable/drivable as a library (package products, public APIs, progress delegate,
> end-position tracking, concurrency). The **analysis fixes** (false positives) live in
> [`../../PERIPHERY-ANALYSIS-FIXES.md`](../../PERIPHERY-ANALYSIS-FIXES.md) (Concern A). Project doc
> map: [`../../TREESWIFT-PROJECT-MAP.md`](../../TREESWIFT-PROJECT-MAP.md).

This is the reference for **which** library-integration modifications live in the subtree and why. It does NOT cover the branch/rebuild workflow — that moved to dedicated guides (see below).

## What this subtree is

`PeripherySource/periphery/` is a **git subtree** that vendors the **`combine`** branch of the fork [danwood/periphery](https://github.com/danwood/periphery). Vendoring (rather than a remote package) keeps the Treeswift repo self-contained: a fresh clone builds with no network and no extra setup.

`combine` = current upstream Periphery + this glue + the unmerged feature/fix branches + the Treeswift-only retainers. It is validated by a forceRemoveAll → rebuild probe against four historical Prodcore baselines (zero build errors each). Current pin: tag **`treeswift-combine-2026-06-14`** (commit `055609f`).

**Workflow docs (read these for anything operational):**
- Update the subtree when combine advances → [`../../docs/periphery-subtree-maintenance.md`](../../docs/periphery-subtree-maintenance.md)
- Rebuild combine on a new upstream release → [`../../docs/periphery-combine-rebuild.md`](../../docs/periphery-combine-rebuild.md)
- Overall status / what's where → [`../../docs/periphery-operation-status.md`](../../docs/periphery-operation-status.md)

## What belongs here vs. upstream

**Only Treeswift-specific integration changes** (this document's categories) live as glue. Everything else — new scan rules, analysis bug fixes, detection patterns — belongs in the fork as branches and flows in through `combine`. Don't edit analysis logic in the subtree directly; don't catalog analysis fixes here (they go in `PERIPHERY-ANALYSIS-FIXES.md`).

When resolving a subtree-pull conflict: **take the incoming `combine` version for anything not listed below as a Treeswift glue change.** The glue set is small and documented; everything else should match combine exactly.

---

## Modification Categories (the glue)

These are the library-integration changes. They originate from the `treeswift-glue` branch in the fork (and are part of `combine`). ~17 files.

### 1. Package structure — `Package.swift`

Split the `Frontend` executable into `Frontend` (executable, `main.swift` only) + `FrontendLib` (library), and export 10 internal modules as library products: Configuration, SourceGraph, Shared, Logger, Extensions, Indexer, ProjectDrivers, SyntaxAnalysis, XcodeSupport, FrontendLib. This is what lets the Treeswift GUI import Periphery's internals. Load-bearing — must survive every upstream update.

### 2. Location end-position tracking (~3 files)

Track full source ranges (start AND end) for UI presentation.
- `Sources/SourceGraph/Elements/Location.swift` — adds `endLine`/`endColumn`, `@unchecked Sendable`. **End positions are deliberately EXCLUDED from equality/hash** — including them breaks parameter-lookup tests (~58 failures). Keep that exclusion on any merge.
- `Sources/SyntaxAnalysis/SourceLocationBuilder.swift` — `location(from:to:)`.
- `Sources/PeripheryKit/Results/OutputFormatter.swift` — formats end positions.

### 3. Scan progress delegation (~5 files)

GUI progress callbacks without parsing logger output.
- `Sources/Shared/ScanProgressDelegate.swift` — NEW protocol (`didStartInspecting/Building/Indexing/Analyzing`).
- `Sources/Frontend/Project.swift`, `Sources/Frontend/Scan.swift` — public, threaded delegate.
- `Sources/ProjectDrivers/XcodeProjectDriver.swift` — delegate calls + `excludeTests` pass-through.
- `Sources/Frontend/Commands/ScanCommand.swift` — adapts to `Scan.Output`.

### 4. Swift concurrency checkpoints (~4 files)

`try Task.checkCancellation()` at strategic points for responsive cancellation: `Scan.swift`, `Indexer/IndexPipeline.swift`, `Indexer/JobPool.swift`, `SourceGraph/SourceGraphMutatorRunner.swift`.

### 5. Public API exposure (~2 files)

- `Sources/PeripheryKit/ScanResult.swift` — public `Annotation`, `declaration`, `annotation`, init.
- `Sources/SourceGraph/Elements/Declaration.swift` — `@unchecked Sendable`, `location` let→var (for post-creation end-position update).

### 6. Other (~3 files)

- `Sources/Extensions/FilePath+Extension.swift` — `Comparable`.
- `Sources/XcodeSupport/Xcodebuild.swift` — `excludeTests` (build vs build-for-testing).
- `Sources/Indexer/SourceFileCollector.swift` — drop an unused import.

### 7. Syntax end-position extraction (~2 files)

- `Sources/SyntaxAnalysis/DeclarationSyntaxVisitor.swift` — `endPosition` on the visit `parse()` calls.
- `Sources/Indexer/SwiftIndexer.swift` — apply captured end positions to `Declaration.location`.

---

## Consumer-side API coupling

The Treeswift app code in `Treeswift/Core/Analysis/` depends on a few Periphery APIs the glue/upstream changed. When pulling a new `combine`, expect to adapt these (build to find call sites):
- `Scan.perform` returns a `Scan.Output` struct (not a tuple).
- `Reference.name` and `Declaration.name` are non-optional.
- `DeclarationAttribute.name` is internal — use `.description`.
- `Reference.init` takes `name:` as an argument.

## `.build` is gitignored

Only the Periphery **source** is committed (~900KB). The large `.build` artifacts under this directory are gitignored and rebuilt locally — they are NOT in the repo. (The "1.7GB bloat" that once seemed to argue for a remote package was these local artifacts, never version-controlled.)

## References

- Upstream Periphery: https://github.com/peripheryapp/periphery
- Fork (source of the subtree): https://github.com/danwood/periphery (branch `combine`)
- Analysis-fix catalog: [`../../PERIPHERY-ANALYSIS-FIXES.md`](../../PERIPHERY-ANALYSIS-FIXES.md)
