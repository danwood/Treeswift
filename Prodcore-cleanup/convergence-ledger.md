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

| date | total | unused | assignOnly | redunAcc | redunProto | removed | build_errors | broken_files | fixtures | note |
|------|-------|--------|-----------|----------|-----------|---------|--------------|--------------|----------|------|
| 2026-06-10 | 128 | 42 | 5 | 81 | 0 | 115 | 2 | 1 | 0/0 | Baseline after P1–P13 fixes + Issue 14 (nested type as sibling-prop type) + Issue 15 (sole class init). Remaining FP: `PriceValue` (top-level fileprivate struct used as property type in another type) removed while the property stays — Issue 14 only covers same-parent nesting, not top-level types used as property types elsewhere. → next target. |
| 2026-06-10 | — | — | — | — | — | 144 | ~90 | 29 | 0/0 | **REGRESSED ❌ (reverted).** Tried to generalize Issue 14 into a graph-wide "mark used any type used as any property's declaredType" sweep. Mass `markUsed` perturbed `ignoreUnusedDescendents`, surfacing many previously-ignored decls as removable → 144 removed, ~90 errors across 29 files, including a re-regression of the TuneTargetDisplayModels types Issue 14 had fixed. Lesson: broad `markUsed` sweeps are unsafe; keep Issue 14 narrow (same-parent only). |
| 2026-06-10 | 127 | 41 | 5 | 81 | 0 | 114 | **0** | **0** | 0/0 | **CONVERGING ✅.** Reverted the broad sweep; kept Issue 14 narrow. Fixed `PriceValue` precisely: `CodablePropertyRetainer` now also `markRetained`s the concrete type used as a retained Codable/Encodable property's `declaredType` (+ descendants). Full `forceRemoveAll` on all of Prodcore now **builds with zero errors.** Audit 0: `testRetainsCodableProperties`/`FixtureStruct14` uses a built-in (`Int`) property type — custom-type case NOT covered upstream → genuine gap, fix justified; owes a new Periphery test + fixture. Regression test written (`RetentionTest.testRetainsCodablePropertyCustomType` + `FixtureStruct200/201`); runs only on a standalone upstream checkout (subtree isn't `swift test`-buildable in-repo), verified in-repo by E2E. |

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
