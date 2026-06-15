# Rebuilding the `combine` branch on a new upstream Periphery

When a new upstream Periphery release comes out, `combine` (the branch the Treeswift subtree tracks) must be rebuilt on top of it. This is the periodic maintenance task. All work happens in the fork clone `danwood/periphery` (not in Treeswift).

## What `combine` is made of

`combine` = current `upstream/master` + **four** branches merged in. That's it — no loops, no separately-stacked fix commits.

| branch | what | upstream PR |
|---|---|---|
| `fix-unresolvable-subproject-refs` | `try?` driver fix | #1133 |
| `fix-sole-class-init` | retain sole class init | #1134 |
| `redundant-nested` | redundant nested access (#1048 feature) | not yet |
| `treeswift-extras` | **#1132's redundant internal/fileprivate analysis PLUS every Treeswift-only fix**, all in one branch | mixed (see below) |

### Inside `treeswift-extras`

This one branch bundles all the Treeswift-specific code so the rest of the graph stays simple. It is built **on top of `redundant-internal-fileprivate` (#1132)** — because the assign-only fix needs #1132's `isLetBinding` plumbing — with everything else merged in. Contents:

- the **glue** (library integration: Package.swift product split, end-position tracking, ScanProgressDelegate, task-cancellation, public API) — never upstream
- **ObservableMacroRetainer (F1)** + **ProtocolConformanceRetainer (F3)** — Treeswift-only (F1 inert on current upstream toolchain, F3 conflicts with upstream's redundant-protocol diagnostic)
- the full **UsedDeclarationMarker propagation walks (F5/F7/F9/F11/F13)** — only one walk is upstreamable (that's PR #1137, a *separate* `fix-used-marking-propagation` branch); the rest are recall-over-precision
- the **assign-only retention** fix (related upstream PR: #1136, a *separate* `fix-assignonly-init-retained` branch)
- and it carries **#1132** as its base.

So `treeswift-extras` is the single home for everything that is correct for Treeswift's aggressive cleanup but wrong (or moot) for upstream. The clean upstream PRs (#1132/#1133/#1134/#1136/#1137) live on their own separate branches and are NOT folded in here.

## Why a separate `treeswift-extras` instead of stacking everything

Each upstream PR branch must sit on **bare upstream** so it's a clean pull request. But several Treeswift-only fixes depend on each other (the assign-only fix needs #1132). If those dependencies were drawn as independent branches that "secretly contain" each other, the graph became a tangle of loops. Folding all the Treeswift-only code into one branch (`treeswift-extras`) — which is allowed to carry #1132 because it never goes upstream — removes the loops entirely. The result: 4 simple ingredient branches, all off upstream, merged into combine.

## Rebuild procedure

```sh
cd /Users/dwood/code/periphery-dan-private
git fetch upstream
git fetch origin
git branch -f combine-prev origin/combine    # fallback + conflict-resolution source; keep until done
```

1. **Rebase each ingredient branch onto the new upstream.** The three PR/feature branches rebase straightforwardly; `treeswift-extras` is the involved one (it carries #1132 + glue + the fixes, so expect conflicts from upstream API drift):
   ```sh
   for b in fix-unresolvable-subproject-refs fix-sole-class-init redundant-nested redundant-internal-fileprivate; do
     git checkout "$b" && git rebase upstream/master   # resolve, build
   done
   # treeswift-extras is built ON redundant-internal-fileprivate; rebuild it after #1132 is rebased:
   git checkout treeswift-extras && git rebase upstream/master   # heavier; resolve carefully, build + test
   ```
   Build each after rebasing (`DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift build`).

2. **Recreate `combine`** off the new upstream and merge the four branches:
   ```sh
   git checkout combine && git reset --hard upstream/master
   git merge fix-unresolvable-subproject-refs   # clean
   git merge fix-sole-class-init                # clean
   git merge redundant-nested                   # usually clean
   git merge treeswift-extras                   # CONFLICTS (~20 files) — it overlaps the others heavily
   ```
   **Conflict resolution (verified to reproduce combine exactly):** for every conflicted file, take the previous combine's already-resolved version — `git checkout combine-prev -- <file>` then `git add` + commit. The prior combine encodes all the correct unions. (The hard invariant inside those files: end positions stay EXCLUDED from `Location` equality/hash, else ~58 parameter-lookup tests fail.)

3. **Build + full test**: `swift build && swift test`. Self-scan gate: `./.build/debug/periphery scan --quiet --clean-build --strict` → "No unused code detected". Lint: `mise exec -- swiftformat --quiet --strict . && mise exec -- swiftlint lint --quiet --strict`.

4. **Re-prove convergence** (the real acceptance test) — see [periphery-operation-status.md](periphery-operation-status.md) for the forceRemoveAll→rebuild probe against the four Prodcore baselines (R5/R4/R-May/R3). Each must rebuild with **zero build errors** after a full unused-code removal.

5. **Push** (force, since `combine` is rewritten):
   ```sh
   git push -f origin combine
   git branch -D combine-prev   # once you're satisfied
   ```

6. **Update the subtree** in Treeswift — see [periphery-subtree-maintenance.md](periphery-subtree-maintenance.md).

## As upstream merges the PRs

When ileitch merges #1132/#1133/#1134/#1136/#1137, those fixes become part of the new upstream base — so drop the corresponding ingredient branch from the merge list (and from `treeswift-extras`, for the parts it carries). Over time `combine` shrinks toward just `treeswift-extras` (glue + the genuinely-Treeswift-only retainers) on top of upstream.
