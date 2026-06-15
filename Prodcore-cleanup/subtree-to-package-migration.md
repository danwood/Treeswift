> **SUPERSEDED / HISTORICAL (2026-06-14):** This package migration was TRIED then REVERTED — the subtree was kept (self-contained clone-and-build outweighs drift-risk; the 1.7GB bloat rationale below was wrong — it was gitignored .build). Kept only as a record of the experiment. For current practice see [periphery-subtree-maintenance.md](../docs/periphery-subtree-maintenance.md) and [periphery-combine-rebuild.md](../docs/periphery-combine-rebuild.md).

# Migration runbook: Periphery subtree → pinned Swift package

**Status:** PLANNED, not executed. Written 2026-06-14. Do NOT run until the combine count-investigation (assignOnly 5→534, see PERIPHERY-ANALYSIS-FIXES.md "Regression-replay finding 2026-06-14") is resolved.

## Why

`PeripherySource/periphery` is currently a **git subtree** — a full copy of `danwood/periphery` squashed into the Treeswift repo. That made sense when we edited Periphery in-place. We no longer do: all Periphery edits now live as proper branches in `danwood/periphery` (`treeswift-glue`, `redundant-internal-fileprivate`, etc.), merged into `origin/combine`. With `subtree == combine` and no local edits, the subtree is pure liability: silent drift risk, ~1.7 GB of `.build` bloat in the repo path, manual squash-pulls.

Goal: make Treeswift consume Periphery as a **version-pinned dependency** so drift becomes impossible (Package.resolved locks the exact commit) and updates are a one-line pin bump.

## Current wiring (captured 2026-06-14)

- `Treeswift.xcodeproj/project.pbxproj`:
  - `XCLocalSwiftPackageReference` id `CE73423A2E99895400832192`, `relativePath = PeripherySource/periphery`.
  - App target links products: **Configuration, PeripheryKit, SourceGraph, FrontendLib** (FrontendLib is a glue product — load-bearing).
  - Product dependencies appear in two framework sections (app + a second target — verify which: likely the app and a preview/test target).
- The Periphery package's own `Package.swift` exposes those products (glue added FrontendLib + 10 module libraries).
- Periphery itself depends on: swift-system, Yams, AEXML, swift-argument-parser, swift-indexstore, swift-syntax, swift-filename-matcher. (These are Periphery's deps — one level down, normal.)

## Decision: which mechanism

| Option | Drift | Offline | Edit-locally | Notes |
|---|---|---|---|---|
| **Remote SPM** (`danwood/periphery` @ branch/tag combine) | impossible (Package.resolved) | needs network for first resolve / or local mirror | swap to `.package(path:)` while hacking | cleanest; no files in Treeswift repo |
| **Local checkout** of combine at a path | possible unless re-pulled | yes | natural | still a copy on disk |
| **Submodule** @ combine commit | impossible (pinned SHA) | yes (after init) | in-place | clunky UX, easy to forget pointer bump |

Recommended: **Remote SPM pinned to a TAG** (e.g. `combine-2026-06-14`), not a moving branch — a tag is immutable, so resolution is reproducible. Fall back to submodule if offline builds are mandatory.

## Steps (remote-SPM flavor)

1. **Tag combine** in `danwood/periphery`: `git tag combine-YYYY-MM-DD origin/combine && git push origin combine-YYYY-MM-DD`. (Immutable pin.)
2. **In Xcode** (or by editing project.pbxproj): remove the `XCLocalSwiftPackageReference` to `PeripherySource/periphery`; add an `XCRemoteSwiftPackageReference` to `https://github.com/danwood/periphery` with `exactVersion`/`revision` = the tag.
3. **Re-add the same product dependencies** (Configuration, PeripheryKit, SourceGraph, FrontendLib) from the new remote package to the app target (and the second target). Same product names — glue exposes them.
4. **Delete** the `PeripherySource/periphery` directory from the Treeswift repo (and remove it from git: `git rm -r PeripherySource/periphery`). This drops the 1.7 GB `.build` + the squashed source.
5. **Resolve**: `xcodebuild -resolvePackageDependencies` (or Xcode File→Packages→Resolve). Commit the updated `Package.resolved`.
6. **Apply the app-side API adaptations** (the 5 fixes from `/tmp/treeswift-app-api-adaptations.patch`) IF the pinned combine is fresh-upstream-based — `Reference.name`/`Declaration.name` non-optional, `Scan.Output` struct not tuple, `DeclarationAttribute.name` → `.description`, `Reference.init` needs `name:`. (Not needed if pinning the current 47b1a784 subtree state instead.)
7. **Build + smoke-test** the app; run one Prodcore scan to confirm parity.

## Verification

- App builds + links against the remote package (no `PeripherySource/` on disk).
- `Package.resolved` pins the exact combine commit.
- A Prodcore scan runs and matches expected counts (depends on which combine state is pinned — see count investigation).

## Rollback

The subtree is recoverable from git history (`git revert` the removal commit) or re-added via `git subtree add` from `danwood/periphery`. Tag the pre-migration Treeswift commit first.

## Coupling note

Pinning to **combine** pulls in the fresh-upstream Periphery whose scan counts are unexplained (534 assignOnly). To decouple: first migrate the MECHANISM while pinning the **current** proven subtree state (47b1a784), then bump the pin to combine after the investigation clears it.
