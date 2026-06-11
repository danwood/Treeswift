# Prodcore Convergence Ledger

The single source of truth for whether Treeswift + Periphery are **converging toward zero
false positives** on the Prodcore codebase. Every cleanup/fix cycle appends one row. The
supervisor agent (`.claude/agents/cleanup-supervisor.md`) reads and updates this file and
prints the progress table.

## The Goal

A fully correct Periphery + Treeswift must satisfy **both** convergence conditions on Prodcore:

1. **Genuine dead code → 0.** Running scan → remove → rescan repeatedly drives the genuine
   unused-code count down to zero (only real, removable dead code gets removed, and once
   removed it stays gone).
2. **False positives → 0.** A full `forceRemoveAll` removal followed by a Prodcore build
   produces **zero build errors**. Every build error after removal is a false positive: either
   Periphery flagged something it should not have, or Treeswift removed it incorrectly.

**We are NOT done when "only documented false positives remain."** Documented false positives
are bugs that must be FIXED in Periphery/Treeswift until none remain. The ledger's
`build_errors` column must reach **0** and stay there.

## How a Cycle Works (measured loop)

1. Ensure Treeswift built clean AND the running binary is fresh (verify dylib mtime — see
   [[stale-incremental-build]] / `CLEANUP-PROCESS.md`).
2. Clear the Treeswift scan cache, launch fresh, scan Prodcore. Record the summary counts.
3. `forceRemoveAll` on the whole project (root). Build Prodcore. Record `build_errors` =
   number of distinct error lines, and list every broken file.
4. Revert Prodcore (`git restore .`).
5. For each distinct build error: it is a false positive. Diagnose root cause (Periphery
   analysis vs. Treeswift removal), fix it at the source, add a regression fixture, rebuild.
6. Re-run from step 1. The new row must show `build_errors` strictly lower (or equal only if
   the same root cause spans multiple files and is fixed in one shot next cycle).

A cycle is **regression-free** only if no previously-zero error reappears and no fixture fails.

## Metrics Columns

| Column | Meaning |
|--------|---------|
| `date` | Date of the measurement |
| `total` | Total scan results (`totalCount`) |
| `unused` | `.unused` annotation count |
| `assignOnly` | `.assignOnlyProperty` count |
| `redunAcc` | sum of all redundant-accessibility annotations |
| `redunProto` | `.redundantProtocol` count |
| `removed` | items removed by `forceRemoveAll` |
| `build_errors` | distinct build errors after full removal = **surviving false positives** |
| `broken_files` | count of distinct files with errors after removal |
| `fixtures` | regression fixtures passing / total |
| `note` | what changed this cycle |

## Ledger

| date | baseline | total | unused | assignOnly | redunAcc | redunProto | removed | build_errors | broken_files | fixtures | note |
|------|----------|-------|--------|-----------|----------|-----------|---------|--------------|--------------|----------|------|
| 2026-06-10 | HEAD | 128 | 42 | 5 | 81 | 0 | 115 | 2 | 1 | 0/0 | Baseline after P1–P13 fixes + Issue 14 (nested type as sibling-prop type) + Issue 15 (sole class init). Remaining FP: `PriceValue` (top-level fileprivate struct used as property type in another type) removed while the property stays — Issue 14 only covers same-parent nesting, not top-level types used as property types elsewhere. → next target. |
| 2026-06-10 | HEAD | — | — | — | — | — | 144 | ~90 | 29 | 0/0 | **REGRESSED ❌ (reverted).** Tried to generalize Issue 14 into a graph-wide "mark used any type used as any property's declaredType" sweep. Mass `markUsed` perturbed `ignoreUnusedDescendents`, surfacing many previously-ignored decls as removable → 144 removed, ~90 errors across 29 files, including a re-regression of the TuneTargetDisplayModels types Issue 14 had fixed. Lesson: broad `markUsed` sweeps are unsafe; keep Issue 14 narrow (same-parent only). |
| 2026-06-10 | HEAD | 127 | 41 | 5 | 81 | 0 | 114 | **0** | **0** | 0/0 | **CONVERGING ✅.** Reverted the broad sweep; kept Issue 14 narrow. Fixed `PriceValue` precisely: `CodablePropertyRetainer` now also `markRetained`s the concrete type used as a retained Codable/Encodable property's `declaredType` (+ descendants). Full `forceRemoveAll` on all of Prodcore now **builds with zero errors.** Audit 0: `testRetainsCodableProperties`/`FixtureStruct14` uses a built-in (`Int`) property type — custom-type case NOT covered upstream → genuine gap, fix justified; owes a new Periphery test + fixture. Regression test written (`RetentionTest.testRetainsCodablePropertyCustomType` + `FixtureStruct200/201`); runs only on a standalone upstream checkout (subtree isn't `swift test`-buildable in-repo), verified in-repo by E2E. |

### Git-history convergence experiment rows (baseline = `<ID>@<commit>`)

For these rows `build_errors` = **NEW errors only** (post-removal minus the pristine-baseline error
set), so historical package/API breakage never masquerades as a false positive. See
`experiment-log.md` + `experiment-state.json`.

| date | baseline | total | unused | assignOnly | redunAcc | redunProto | removed | build_errors | broken_files | fixtures | note |
|------|----------|-------|--------|-----------|----------|-----------|---------|--------------|--------------|----------|------|
| 2026-06-11 | R3@23ad2547 | 2819 | 862 | 2 | 1939 | 0 | 849 | **0** | **0** | n/a | Pass 1 (UNUSED-ONLY). Biggest/oldest baseline (precedes the 04-14→04-17 massive cleanup). Pristine built clean (signing off + pin). **Unused-only removal: 849 deleted / 235 files, builds clean, 0 FPs** — core claim proven even here. (Full removal at pass 1 had 4 access-control errors → split unused-first.) Committed `ad3db3b6`. |
| 2026-06-11 | R3@23ad2547 | 1072 | 9 | 4 | 1059 | 0 | 1068 | **0** | **0** | n/a | Pass 3. redunAcc 2008→1059. 1068 / 146 files, clean. Committed `00df378b`. |
| 2026-06-11 | R3@23ad2547 | 34 | 0 | 4 | 30 | 0 | 30 | **0** | **0** | n/a | Pass 4. unused→0, redunAcc 1059→30. 30 / 9 files, clean. Committed `7742d491`. |
| 2026-06-11 | R3@23ad2547 | 4 | 0 | 4 | **0** | 0 | — | **0** | **0** | n/a | **CONVERGED ✅ (cold verdict).** unused 862→0, redunAcc 1939→0, **~3964 decls removed** across 4 passes, build clean every pass, **0 false positives** — after fixing F20 (and F18/F19 carried from R-May). Floor 4 assignOnly. The biggest/oldest baseline; full convergence. |
| 2026-06-11 | R3@23ad2547 | 2036 | 8 | 4 | 2008 | 0 | 2017 | **0** | **0** | n/a | Pass 2 (redundant-accessibility). Surfaced **F20** — top-level `fileprivate` type's extension-method result not cascaded (`computeSectionGroups` → "method must be declared fileprivate"). Fixed `CodeModificationHelper.cascadeFileprivateToReferencingFunctions`. After fix: full forceRemoveAll 2017 / 307 files, **builds clean, 0 FPs.** Committed `8f659673`. (F18+F19 from R-May also active; PreviewSettings FP from pass-1 full-removal was on already-removed code, gone.) |
| 2026-06-11 | R5@a1711d27 | 740 | 271 | 5 | 464 | 0 | 721 | **0** | **0** | n/a | Pass 1. Pristine R5 built clean (empty error set → absolute build semantics). forceRemoveAll deleted 721 decls / 167 files (4894 lines); Prodcore **builds clean, zero false positives.** 5 `redundantPublicAccessibility` ghost modifications (no-op, F17 guard) left unapplied in Main/Gear/{ProductCatalogDetailView,ProductCategoriesView,ProductsLibraryView} — will re-surface on rescan; watch whether they block redunAcc→0. Committed `137fd70d`. |
| 2026-06-11 | R5@a1711d27 | 105 | 1 | 5 | 99 | 0 | 100 | **0** | **0** | n/a | Pass 2. Rescan unused 271→1, redunAcc 464→99 (both ↓). forceRemoveAll 100 more / 17 files, builds clean, 0 FPs, 0 ghosts (pass-1 ghosts resolved). Committed `1f12d964`. CONVERGING ✅. |
| 2026-06-11 | R5@a1711d27 | 10 | 0 | 5 | 5 | 0 | 5 | **0** | **0** | n/a | Pass 3. Rescan unused 1→0, redunAcc 99→5. forceRemoveAll 5 / 3 files, builds clean. Committed `24a02d22`. |
| 2026-06-11 | R4@20fb9b87 | 742 | 272 | 5 | 465 | 0 | 723 | **0** | **0** | n/a | Pass 1. Pristine build needed `CODE_SIGNING_ALLOWED=NO` (R4 predates the 06-01 root-xcconfig; signing mismatch, orthogonal to analysis) → then clean. forceRemoveAll 723 / 167 files (−4903 lines), Prodcore **builds clean, 0 false positives** (5 access-control ScanCache ghosts, known artifact). Committed. |
| 2026-06-11 | R4@20fb9b87 | 105 | 1 | 5 | 99 | 0 | 100 | **0** | **0** | n/a | Pass 2. unused 272→1, redunAcc 465→99. 100 / 17 files, clean, 0 ghosts. Committed `c7bd9247`. CONVERGING ✅. |
| 2026-06-11 | R4@20fb9b87 | 10 | 0 | 5 | 5 | 0 | 5 | **0** | **0** | n/a | Pass 3. unused 1→0, redunAcc 99→5. 5 / 3 files, clean. Committed `4a422c93`. |
| 2026-06-11 | R4@20fb9b87 | 5 | 0 | 5 | **0** | 0 | — | **0** | **0** | n/a | **CONVERGED ✅ (cold rescan).** Cold-cache discipline applied (kill app + delete cache by exact name) — no phantom-ghost detour this time. unused 272→0, redunAcc 465→0, ~828 decls removed across 3 passes, build clean every pass, **0 false positives.** Floor 5 assignOnly. |
| 2026-06-11 | R-May@96e372e4 | 203 | 8 | 3 | 192 | 0 | 200 | **0** | **0** | n/a | Pass 2. unused 260→8, redunAcc 1330→192. 200 / 46 files, clean, 0 ghosts (F18/F19 holding). Committed `ed9292e0`. CONVERGING ✅. |
| 2026-06-11 | R-May@96e372e4 | 27 | 1 | 3 | 23 | 0 | 24 | **0** | **0** | n/a | Pass 3. unused 8→1, redunAcc 192→23. 24 / 9 files, clean. Committed `0d34fbfe`. |
| 2026-06-11 | R-May@96e372e4 | 3 | 0 | 3 | **0** | 0 | — | **0** | **0** | n/a | **CONVERGED ✅ (cold verdict).** unused 260→0, redunAcc 1330→0, **~1810 decls removed** across 3 passes, build clean every pass, **0 false positives** — after fixing two real Treeswift removal bugs (F18 sync-folder deletion, F19 extension-public cascade). Floor 3 assignOnly. The dirtiest baseline; full convergence. |
| 2026-06-11 | R-May@96e372e4 | 1593 | 260 | 3 | 1330 | 0 | 1586 | **0** | **0** | n/a | Pass 1. Dirtiest baseline (redunAcc 1330; redundantInternal 1111). Surfaced **two real Treeswift removal bugs, both fixed at root**: **F18** (sync-folder `membershipExceptions` files deleted → "Build input files cannot be found"; fixed `XcodeProjectFileChecker`) and **F19** (`public` left on extension members after type downgrade → "cannot declare a public initializer in an extension with internal requirements"; fixed `CodeModificationHelper.cascadePublicStripFromExtensions`). Unused-only removal was clean (257, 0 errors) — core claim independent of the access-control bug. After both fixes + a clean pristine run: 1586 deleted / 296 files, **builds clean, 0 false positives.** Committed `13b225cc`. (Brace-corruption errors seen mid-debug were driver contamination — scanning a half-removed tree — NOT a Treeswift bug.) |
| 2026-06-11 | R5@a1711d27 | 5 | 0 | 5 | **0** | 0 | 0 | **0** | **0** | n/a | **CONVERGED ✅ (cold rescan).** Passes 3→4 appeared stuck at redunAcc=5 with 5 no-op ghosts in StatusInfo/ProgramDisplayModel/TuneTargetDisplayModels — but that was a **stale Treeswift ScanCache** (the 153 MB `scan-cache-<UUID>.json` survived in-loop `rm` because the zsh glob errored after the cache rewrote; incremental cache re-served already-fixed access-control warnings against stale source positions). After killing the app + deleting the cache file by exact name and a COLD rescan: **unused=0, redunAcc=0, assignOnly=5** (floor). Total: unused 271→0, redunAcc 464→0, **776 decls removed**, build clean every pass, **0 false positives.** Finding: ScanCache invalidation is incomplete for in-place access-keyword rewrites (cache bug, not a removal/analysis bug). |

### Genuine-dead-code convergence probe (second condition) — 2026-06-10

Multi-pass scan→remove→rescan on Prodcore (in-place, then reverted):

| pass | scan unused | removed | build after | rescan unused | rescan total |
|------|-------------|---------|-------------|---------------|--------------|
| 1 | 41 | 114 | ✅ clean | 0 | 7 |
| 2 | 0 (residual redundant-acc) | 2 | ✅ clean | — | 5 |

**Genuine dead code → 0 in one removal pass, with ZERO resurfacing ghosts.** `.unused` went
41 → 0 and stayed 0; total 127 → 7 → 5. The 5 residual are all `assignOnlyProperty` (not removed by
`forceRemoveAll`'s default filter — they need an explicit annotation filter and per-item review,
not a false positive). Both passes built clean.

### Committed cleanup + convergence to the true floor — 2026-06-10

The cleanup was then **committed for real** (not reverted), driving the live warning count down:

| step | Prodcore total | unused | redundant-acc | assignOnly | note |
|------|----------------|--------|---------------|------------|------|
| baseline | 127 | 41 | 81 | 5 | starting dead-code count |
| committed removals (Prodcore `f7991ca5`) | — | — | — | — | 727 lines of dead code deleted, builds clean |
| rescan | 7 | 0 | 2 | 5 | 2 second-order redundant-acc surfaced |
| + actor ghost fix (Treeswift) + apply (Prodcore `942899a1`) | **5** | **0** | **0** | **5** | converged |

Reaching the floor required fixing **F17** — `actor TourStatsCache` flagged
`redundantInternalAccessibility` was a Treeswift *no-op ghost* (actors are classified `.class`, but
the rewrite searched for the `class` keyword on an `actor` line and gave up → re-flagged forever).
Fixed (`insertAccessKeyword` now handles `class`/`actor`) + a general no-op-detection guard. After
the fix the actor was rewritten to `fileprivate actor`, built clean, and the warning did NOT
re-appear on rescan.

**TRUE FLOOR REACHED: 0 unused, 0 redundant-accessibility, 5 `assignOnlyProperty`** (the latter
have no automated removal logic by design — see `docs/proposals/algorithmic-warning-fixes.md`).
Both convergence conditions met: false positives = 0, genuine dead code → 0 with no oscillation.

## Open False Positives (must reach empty)

Tracked live; each must end as a Periphery/Treeswift fix + regression fixture, NOT a "skip".

**Currently: none.** A full `forceRemoveAll` of all Prodcore builds with zero errors (2026-06-10).

### Resolved

1. ~~**PriceValue top-level-type-as-property-type**~~ — `ClaudePriceLookupService.swift`. FIXED by
   extending `CodablePropertyRetainer` to retain the declared type (+ descendants) of each retained
   Codable/Encodable property. The precise (retained-property-only) approach avoids the over-removal
   regression that a graph-wide `markUsed` sweep caused (see reverted ledger row).

## Outstanding work (not false positives, but required to call this "done")

- **Regression fixtures: 0/0 — build them.** Need a `Prodcore-cleanup/fixtures/` corpus AND
  upstream Periphery tests for Issues 13/14/15 and the Codable-type-retention fix, mirroring
  `Tests/PeripheryTests/RetentionTest.swift` + `Tests/Fixtures/Sources/RetentionFixtures/`.
  Specifically the Codable fix owes a fixture extending `FixtureStruct14` with a custom-struct
  property type that would otherwise be unused.
- **Genuine dead-code convergence not yet proven.** build_errors is 0, but we have not yet shown
  that committing real removals + rescanning drives the genuine `.unused` count to a stable zero.
  That is the second convergence condition and is still open.
