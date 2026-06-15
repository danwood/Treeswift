# Rebuilding the `combine` branch on a new upstream Periphery

When a new upstream Periphery release comes out, `combine` (the branch the Treeswift subtree tracks) must be rebuilt on top of it. This is the periodic, non-trivial maintenance task. All work happens in the fork clone `danwood/periphery` (not in Treeswift).

## What `combine` is made of

`combine` = current `upstream/master` + four merged feature branches + a stack of glue/fix commits on top. Verified composition (as of combine `055609f`):

**Merged branches** (each based on `upstream/master`):
| branch | what | upstream PR |
|---|---|---|
| `treeswift-glue` | library-integration glue (Package.swift product split, end-position tracking, ScanProgressDelegate, task-cancellation, public API) | none (never upstream) |
| `fix-unresolvable-subproject-refs` | `try?` driver fix | #1133 |
| `fix-sole-class-init` | retain sole class init | #1134 |
| `redundant-internal-fileprivate` | redundant internal/fileprivate analysis | #1132 |
| `redundant-nested` | redundant nested access (#1048 feature) | not yet |

**Fix commits/branches layered on top** (these are the ones the replay proved necessary — they are NOT all upstreamable; combine optimizes recall, upstream precision):
| source | what | status |
|---|---|---|
| `treeswift-observable-protocol-retainers` (branch) | ObservableMacroRetainer (F1) + ProtocolConformanceRetainer (F3) | Treeswift-only (F1 inert upstream, F3 conflicts with redundant-protocol diagnostic) |
| `treeswift-used-marking-walks` (branch) | the full 5 UsedDeclarationMarker propagation walks | only 1 walk upstreamable (#1137); the rest are recall-over-precision |
| `treeswift-assignonly-retention` (branch, **stacked on #1132 + glue**) | retain initialized constant assign-only properties | entangled with glue + #1132's `isLetBinding` plumbing, so this branch is NOT based on bare upstream — it is built on `redundant-internal-fileprivate` (#1132) with `treeswift-glue` merged in, then the fix on top. (related upstream PR: #1136) |

Before rebuilding, keep a ref to the current combine (e.g. `git branch combine-prev origin/combine`) — it's both the conflict-resolution source (step 2) and the fallback if a rebuild goes sideways.

## Rebuild procedure

```sh
cd /Users/dwood/code/periphery-dan-private
git fetch upstream
git fetch origin
```

1. **Rebase each feature/glue branch onto the new upstream** (or recreate if a rebase is messy). Order doesn't matter for the independent ones; do them one at a time and fix any conflicts from upstream API changes:
   ```sh
   for b in treeswift-glue fix-unresolvable-subproject-refs fix-sole-class-init \
            redundant-internal-fileprivate redundant-nested \
            treeswift-observable-protocol-retainers treeswift-used-marking-walks; do
     git checkout "$b" && git rebase upstream/master   # resolve, build, test
   done
   ```
   Build each after rebasing (`DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer swift build`). Upstream API drift is the usual conflict source.

2. **Recreate `combine`** off the new upstream and merge the branches in. Most branches fork independently off upstream, so this is a series of merges — NOT a clean fast-forward chain. Several conflict (the branches edit overlapping files); the verified resolution is below.
   ```sh
   git branch -f combine upstream/master
   git checkout combine
   git merge treeswift-glue                    # clean
   git merge fix-unresolvable-subproject-refs  # clean
   git merge fix-sole-class-init               # clean
   git merge redundant-internal-fileprivate    # CONFLICT ~2 files (Project.swift, main.swift) — glue vs #1132 public-API
   git merge redundant-nested                  # CONFLICT ~19 files — redundant-nested carries an OLDER copy of the int/fileprivate feature
   git merge treeswift-observable-protocol-retainers  # clean
   git merge treeswift-used-marking-walks      # clean
   git merge treeswift-assignonly-retention    # CONFLICT ~1 file (Declaration.swift) — stacked on #1132+glue, merge AFTER those
   ```

   **Conflict resolution (verified — this dry-run reproduces combine exactly):**
   - The clean way is to take the **already-resolved version from the previous `combine`** for every conflicted file: `git checkout <old-combine-ref> -- <file>` then `git add` + commit. (Keep a ref/branch of the prior combine before `branch -f` overwrites it.) This works because the prior combine encodes all the correct unions.
   - If resolving from scratch instead: glue + #1132 conflicts are **unions** — glue adds end-position/progress/public-API, #1132 adds the analysis; keep BOTH. The redundant-nested conflict: take **#1132's** marker files (RedundantInternal/Fileprivate/Public, shared helpers) — nested's are older; keep only nested's genuinely-new umbrella mutator + flags. For `treeswift-assignonly-retention`, the merged `DeclarationSyntaxVisitor`/`Declaration` must have BOTH `isLetBinding` (#1132) AND the `endPosition`/`location(from:to:)` glue code.
   - The hard rule that survives all of it: **end positions stay EXCLUDED from `Location` equality/hash** (else ~58 parameter-lookup tests fail).

3. **Build + full test**: `swift build && swift test`. Then run the upstream self-scan gate: `./.build/debug/periphery scan --quiet --clean-build --strict` → "No unused code detected". Lint: `mise exec -- swiftformat --quiet --strict . && mise exec -- swiftlint lint --quiet --strict`.

4. **Re-prove convergence** (the real acceptance test) — see [periphery-operation-status.md](periphery-operation-status.md) for the forceRemoveAll→rebuild probe against the four Prodcore baselines (R5/R4/R-May/R3). Each must rebuild with **zero build errors** after a full unused-code removal. This is what validates that combine's recall-tuned analysis is still safe.

5. **Push** (force, since `combine` is rewritten). Keep the old combine as a fallback ref first:
   ```sh
   git branch -f combine-prev origin/combine   # fallback to the previous combine, just in case
   git push -f origin combine
   ```

6. **Update the subtree** in Treeswift — see [periphery-subtree-maintenance.md](periphery-subtree-maintenance.md).

## Why so manual

Combine deliberately carries fixes that are correct for Treeswift's aggressive cleanup but wrong (or moot) for upstream — so they can't all become upstream PRs that would eventually flow back automatically. Until/unless upstream adopts equivalents, this rebuild keeps them layered on each new upstream. As upstream merges the PR'd subset (#1132/#1133/#1134/#1136/#1137), drop those branches from the merge list — `combine` shrinks toward glue + the Treeswift-only retainers.
