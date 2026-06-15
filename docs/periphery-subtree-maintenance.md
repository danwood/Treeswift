# Maintaining the Periphery subtree

Treeswift vendors its build of [Periphery](https://github.com/peripheryapp/periphery) as a **git subtree** at `PeripherySource/periphery/`, referenced by `Treeswift.xcodeproj` as a local Swift package. This keeps the repo self-contained: a fresh clone builds with no extra setup and no network dependency.

## What the subtree contains

The subtree tracks the **`combine` branch** of the fork [`danwood/periphery`](https://github.com/danwood/periphery), NOT vanilla upstream. `combine` =

- current upstream Periphery (`peripheryapp/periphery` master), plus
- the library-integration "glue" that lets Treeswift consume Periphery as a library (Package.swift product split, end-position tracking, `ScanProgressDelegate`, task-cancellation, public API), plus
- the unmerged feature/fix branches (redundant internal/fileprivate, sole-class-init, assign-only retention, the `@Observable`/protocol/used-marking retainers, redundant-nested).

This fix set is validated by a full forceRemoveAll → rebuild probe against four historical Prodcore baselines (zero build errors each). Combine deliberately optimizes **recall** (catch all dead code safely for aggressive cleanup), which is why several of its fixes are NOT appropriate for upstream Periphery (which optimizes precision). See [periphery-operation-status.md](periphery-operation-status.md).

## Remotes (already configured in this repo)

- `danwood-fork` → https://github.com/danwood/periphery (the fork; source of the subtree)
- `periphery-upstream` → https://github.com/peripheryapp/periphery.git (vanilla upstream, reference only)

## Updating the subtree

When the `combine` branch in the fork advances (new fixes, or a rebase onto newer upstream):

```sh
git fetch danwood-fork combine
git subtree pull --prefix=PeripherySource/periphery danwood-fork combine --squash \
  -m "Update Periphery subtree to combine"
```

Then:
1. Resolve any conflicts (rare — usually only when the Treeswift app's consumer code in `Treeswift/Core/` depends on a Periphery API that changed).
2. If the Periphery API changed, adapt the consumer code in `Treeswift/Core/Analysis/` (e.g. past drift: `Reference.name`/`Declaration.name` became non-optional, `Scan.Output` became a struct, `Reference.init` requires `name:`). Build to find the call sites.
3. Build the app (`Treeswift` scheme) and run a Prodcore scan to confirm parity before committing.

## Current pin

The subtree currently equals fork `combine` at commit `055609f`. The squash-commit message from each `git subtree pull` records which combine commit was pulled, so "what the subtree is" is always recoverable from the Treeswift git log.

## Why subtree (not a remote Swift package)

A remote-pinned-package setup was tried and reverted. It removed drift-risk but gave up the self-contained clone-and-build property (offline build; no network needed on a fresh checkout), which matters more for this project — especially for anyone else getting the source. The build-artifact "bloat" that seemed to motivate the package move was gitignored `.build` (never in the repo); the subtree's real source footprint is small. The subtree's only genuine downside is drift-risk, which is acceptable and could be guarded with a CI check that the subtree matches `danwood-fork/combine` if ever needed.

## Editing Periphery itself

Don't edit Periphery in the subtree directly. Make changes as branches in the fork `danwood/periphery`, merge them into `combine`, then pull the subtree. This keeps the fork the single source of truth and the subtree a clean mirror.
