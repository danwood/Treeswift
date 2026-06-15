# Rebuilding the `combine` branch on a new upstream Periphery

When a new upstream Periphery release comes out, `combine` (the branch the Treeswift subtree tracks) must be rebuilt on top of it. This is the periodic, non-trivial maintenance task. All work happens in the fork clone `danwood/periphery` (not in Treeswift).

## What `combine` is made of

`combine` = current `upstream/master` + four merged feature branches + a stack of glue/fix commits on top. Verified composition (as of tag `treeswift-combine-2026-06-14` = `055609f`):

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

The whole thing is also pinned by tag `treeswift-combine-2026-06-14` → use it as the ultimate reference if a rebuild goes sideways.

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

2. **Recreate `combine`** off the new upstream and merge them in:
   ```sh
   git branch -f combine upstream/master
   git checkout combine
   git merge treeswift-glue
   git merge fix-unresolvable-subproject-refs
   git merge fix-sole-class-init
   git merge redundant-internal-fileprivate
   git merge redundant-nested        # take #1132's marker files on conflict; nested is additive
   git merge treeswift-observable-protocol-retainers
   git merge treeswift-used-marking-walks
   git merge treeswift-assignonly-retention   # already stacked on #1132+glue; merge AFTER those two are in
   ```
   Conflict guidance: glue + #1132 overlap in ~8 files (Declaration, OutputFormatter, ScanResult, DeclarationSyntaxVisitor, SourceGraphMutatorRunner, etc.) — UNION both sides (glue adds end-position/progress/public-API, the features add analysis). Keep glue's decision that end positions are EXCLUDED from `Location` equality/hash (else ~58 parameter-lookup tests fail). For `treeswift-assignonly-retention`, the correct merged `DeclarationSyntaxVisitor`/`Declaration` has BOTH `isLetBinding` (from #1132) AND the `endPosition`/`location(from:to:)` glue code — that branch already carries the resolved versions, so prefer them on conflict.

3. **Build + full test**: `swift build && swift test`. Then run the upstream self-scan gate: `./.build/debug/periphery scan --quiet --clean-build --strict` → "No unused code detected". Lint: `mise exec -- swiftformat --quiet --strict . && mise exec -- swiftlint lint --quiet --strict`.

5. **Re-prove convergence** (the real acceptance test) — see [periphery-operation-status.md](periphery-operation-status.md) for the forceRemoveAll→rebuild probe against the four Prodcore baselines (R5/R4/R-May/R3). Each must rebuild with **zero build errors** after a full unused-code removal. This is what validates that combine's recall-tuned analysis is still safe.

6. **Push + re-tag**:
   ```sh
   git push -f origin combine
   git tag treeswift-combine-<YYYY-MM-DD> combine && git push origin treeswift-combine-<YYYY-MM-DD>
   ```

7. **Update the subtree** in Treeswift — see [periphery-subtree-maintenance.md](periphery-subtree-maintenance.md).

## Why so manual

Combine deliberately carries fixes that are correct for Treeswift's aggressive cleanup but wrong (or moot) for upstream — so they can't all become upstream PRs that would eventually flow back automatically. Until/unless upstream adopts equivalents, this rebuild keeps them layered on each new upstream. As upstream merges the PR'd subset (#1132/#1133/#1134/#1136/#1137), drop those branches from the merge list — `combine` shrinks toward glue + the Treeswift-only retainers.
