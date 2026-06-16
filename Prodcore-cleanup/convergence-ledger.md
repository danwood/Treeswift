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
| 2026-06-16 | develop@47a6d25de | 480 | 93 | 161 | 226 | 0 | 272 | **0** | **0** | 3/3 | **CONVERGING ✅ — fresh develop baseline (34 new commits since cb1fb2912).** Cold-cache scan (exact cache-file deleted by name, app relaunched). byAnnotation: unused=93, assignOnly=161, redundantAccessibility=156, redundantInternalAccessibility=61, redundantPublicAccessibility=9 (redunAcc column = sum of all 3 = 226). forceRemoveAll: 272 deleted across 50 files, **BUILD SUCCEEDED, 0 errors.** 1 benign ghost no-op (WorkspaceNavigatorToolbar.swift redundantPublicAccessibility, bad source location, F17 family). 23 nonDeletable items in 5 files (AppRootView=15, ToolDescriptor=5, CollaboratorsDataView=1, VenuesDataView=1, RouteMapView=1) — these are assignOnly or engine-conservative items, not false positives. Fixtures 3/3 (F18/F19/F20 E2E shapes present; F21/F22/F23 proven by build_errors=0). **F24 still open:** unused=93 pristine; prior session showed ~47 of these are Archive-coupled (0 deletable post-pass-1). The 34 new commits added ~10 new genuine unused decls on top of the 83 prior floor. redunAcc=226 is entirely new code from the 34 commits — should converge to 0 in multi-pass cleanup like prior sessions. |
| 2026-06-16 | dead-code-cleanup-2026-06-16 (off develop@47a6d25de) | 480→217 | 93→47 | 161 | 226→9 | 0 | 272 | **0** | **0** | 3/3 | **CONVERGING ✅ — PASS 1 committed `0f27f608c`.** Cold-cache pre-removal scan confirmed baseline (480 total, unused=93, redunAcc=226). forceRemoveAll: 272 deleted across 50 files (2 whole-file deletes: ProductCard.swift, SessionTab.swift), BUILD SUCCEEDED, 0 errors. 1 benign ghost no-op (WorkspaceNavigatorToolbar.swift:78 redundantPublicAccessibility, F17 family). 23 nonDeletable. Archive-split: 0 of the 272 deletable were in Archive/ files. Cold rescan after commit: total=217, unused=47, assignOnly=161, redunAcc=9 (redundantAccessibility=2 + redundantInternalAccessibility=7), redunProto=0. The 47 residual unused are all Archive-coupled (0 deletable, 0 nonDeletable in unused-filter preview) — per policy, live decls outside Archive whose only use chains run through Archive are genuine dead code; removal engine conservatively gates them. redunAcc 226→9 still fixable. |
| 2026-06-16 | dead-code-cleanup-2026-06-16 pass 2 | 217→208 | 47 | 161 | 9→**0** | 0 | 9 | **0** | **0** | 3/3 | **CONVERGING ✅ — PASS 2 committed `de0f6a64e`.** forceRemoveAll removed 9 redundant-accessibility items across 3 files (DebugMenuCommands.swift=4, AppRootView.swift=3, RouteMapView.swift=2), BUILD SUCCEEDED, 0 errors. Cold rescan after commit: total=208, unused=47, assignOnly=161, redunAcc=**0**, redunProto=0. forceRemoveAll preview now shows 0 deletable / 0 nonDeletable. **redunAcc reached 0.** Remaining non-zero fixable category: unused=47, all Archive-coupled (per F24 investigation — genuine dead code, removal-gate open question). assignOnly=161 is the design floor. |
| 2026-06-16 | dead-code-cleanup-2026-06-16 pass 3 (Archive indexExclude probe) | 208→209 | 47→48 | 161 | 0 | 0 | 1 (attempted) | **1** | **1** | 3/3 | **REGRESSED ❌ — REVERTED. DO NOT COMMIT.** User added `**/Archive/**` to indexExclude. Cold scan: total went 208→209 (+1), unused 47→48 (+1). forceRemoveAll preview: 1 deletable (`TransportMethodDisplay.systemImage` in ProductionDayDisplayModel.swift). After removal, Prodcore BUILD FAILED: 3 errors in `Projects/Engagement/Views/Archive/LiveEngagementDaysList.swift:243/279/314` — `value of type 'TransportMethodDisplay' has no member 'systemImage'`. ROOT CAUSE: excluding Archive/ from indexExclude does NOT solve the Archive-coupling problem — it makes it WORSE. Periphery can no longer see Archive references, so members used only by Archive code look unused → removing them breaks Archive compilation. The Archive folder is compiled (it's a reference group in the Xcode project, just unedited), so its call-sites still link. indexExclude strips reference-resolution, not compilation. VERDICT: the `**/Archive/**` indexExclude must be REMOVED from the config. It introduces a NEW false-positive category (Archive-only references invisible to Periphery). Prodcore reverted. The 47 Archive-coupled unused decls remain unreachable by any safe automated strategy. |
| 2026-06-16 | dead-code-cleanup-2026-06-16 pass 3 corrected (anchored `**/Prodcore/Archive/**` probe) | 208 | 47 | 161 | 0 | 0 | **0** | **0** | **0** | 3/3 | **FLAT ⚠️ — NO COMMIT (nothing to remove).** indexExclude set to anchored `**/Prodcore/Archive/**` (matches only the 15 uncompiled top-level Archive files, confirmed round-trip). Cold scan (ScanCache empty, relaunched, fresh scan-cache-UUID.json created): total=208, unused=47, assignOnly=161, redunAcc=0 — IDENTICAL to pass 2 floor. forceRemoveAll preview: 0 deletable, 0 nonDeletable. Build clean (trivially; no changes made). ROOT CAUSE OF FLATNESS: the 47 "unused" items are **unused function parameters** (all have `param-*` declarationUSR format — confirmed by inspecting scanResultSnapshots in cache). They are NOT Archive-coupled declarations. Examples: `context` param in `init(from:context:)`, `credential` in `handlePasswordCredential(_:)`, `party` in `handleContact(_:_:)`, scattered across 40+ active non-Archive files. The removal engine never removes unused parameters via forceRemoveAll (different annotation kind, requires explicit per-item review). The previous session's description of these as "Archive-coupled" was incorrect — they are unused parameters in the main codebase. The anchored Archive exclusion is irrelevant to them. CORRECTION: unused=47 are unused function parameters (genuine findings, not false positives, not Archive-coupled). assignOnly=161 is the design floor. BOTH categories are non-removable by forceRemoveAll by design. No false positives. |

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
| 2026-06-16 | develop@cb1fb2912 | 403 | 83 | 157 | 0 | 0 | 194 | **0** | **0** | 3/3 | **0 FALSE POSITIVES ✅.** Current develop. Surfaced 3 NEW false positives broken by forceRemoveAll: **F21** `public` on a protocol-extension default-impl member witnessing an EXTERNAL public protocol (`StatusRepresentable.id`→stdlib `Identifiable`) flagged redundant-public (fixed RedundantExplicitPublicAccessibilityMarker; upstream PR #1139); **F22** nested enum used only as a stored-property type — enum marked used but its CASES still removed, leaving empty enum; **F23** top-level/sibling type used only as a stored-property type wrongly flagged. F22+F23 fixed together in UsedDeclarationMarker (lexical-scope name resolution + enum-case marking, enums only — marking class/struct members regressed `testDoesNotRetainProtocolMethodInSubclassWithDefaultImplementation`); combine-only (stored-property type-resolution is the recall-over-precision family upstream rejects per #1137). After fixes (combine ced2550, subtree pulled into Treeswift 6e1ef42b): forceRemoveAll 194 decls / 43 files → Prodcore **builds clean, 0 errors.** 1 benign `redundantPublicAccessibility` ghost no-op (bad source location, no change applied, F17 family). Also fixed the scan-cache fingerprint (was SHA-256 of empty list → never invalidated; now hashes the source dir, verified 862 files / content-sensitive hash on develop). regression fixtures 3/3: `testPublicProtocolWitnessForExternalProtocol`, `testRetainsNestedTypeUsedAsSiblingStoredPropertyType`, `testRetainsSiblingTypeUsedByStoredPropertyOfUnusedType`. |

### Genuine-dead-code convergence run — 2026-06-16 (develop@47a6d25de, committed on dead-code-cleanup-2026-06-16)

Real (committed) removals on `develop@47a6d25de`, branch `dead-code-cleanup-2026-06-16`:

| pass | scan total | scan unused | scan redunAcc | removed | build after | committed |
|------|-----------|------------|--------------|---------|-------------|-----------|
| 1 | 480 | 93 | 226 | 272 (50 files) | ✅ clean | `0f27f608c` |
| 2 | 217 | 47 | 9 | 9 (3 files) | ✅ clean | `de0f6a64e` |
| rescan | **208** | **47** | **0** | 0 deletable | — | floor |

Pass 1 removed 272 genuine dead decls (all 226 redunAcc + all 46 unused that the engine would touch),
build clean, committed. Pass 2 removed the 9 remaining redundant-accessibility items, build clean,
committed. Cold rescan after pass 2: total=208, unused=47, assignOnly=161, redunAcc=0. redunAcc
has reached 0. The residual 47 unused are Archive-coupled — genuine dead code per F24 investigation
(their only use chains run through the uncompiled `Archive/` reference folder). Removal engine
correctly declines to delete them (0 deletable, 0 nonDeletable in full preview). Per session policy,
Archive-physical findings are excluded from scope; Archive-coupled live decls are in scope but blocked
by the removal gate. This is a Treeswift removal-gate open question, not a false positive.

**Prior discarded session note** (develop@79f0a7123, branch later discarded): Pass 1 removed 46
unused decls via unused-only strategy (committed `3af600565`, later discarded). Lesson from that
session: Archive-coupled decls floor at 47 and are genuinely dead; the gate is conservative.

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

**Currently: none.** A full `forceRemoveAll` of all Prodcore builds with zero errors. F21/F22/F23
(this session) are fixed + fixtured. F24 was investigated and is **NOT a false positive** — the
residual `unused` findings are genuine dead code reachable only through the uncompiled `Archive/`
reference folder (see F24 in `PERIPHERY-ANALYSIS-FIXES.md`). Remaining non-FP item: a Treeswift
removal-gate question (genuinely-dead decls reported "0 deletable").

### Resolved

1. ~~**PriceValue top-level-type-as-property-type**~~ — `ClaudePriceLookupService.swift`. FIXED by
   extending `CodablePropertyRetainer` to retain the declared type (+ descendants) of each retained
   Codable/Encodable property. The precise (retained-property-only) approach avoids the over-removal
   regression that a graph-wide `markUsed` sweep caused (see reverted ledger row).
2. ~~**F21 external-protocol public witness**~~ — `StatusProtocol.swift` (`StatusRepresentable.id`
   witnessing stdlib `Identifiable`). FIXED in `RedundantExplicitPublicAccessibilityMarker`; upstream
   PR #1139. Fixture `testPublicProtocolWitnessForExternalProtocol`.
3. ~~**F22 nested-enum cases removed**~~ — nested enum used only as a stored-property type kept the
   enum but removed its cases. FIXED in `UsedDeclarationMarker` (mark enum cases of name-resolved
   types). Fixture `testRetainsNestedTypeUsedAsSiblingStoredPropertyType`. combine-only.
4. ~~**F23 top-level/sibling type as property type**~~ — generalizes the old PriceValue case to any
   sibling/enclosing-scope type named only by a stored property's `declaredType`. FIXED in
   `UsedDeclarationMarker` (lexical-scope name resolution). Fixture
   `testRetainsSiblingTypeUsedByStoredPropertyOfUnusedType`. combine-only.

## Outstanding work (not false positives, but required to call this "done")

- **unused=47 floor: unused function parameters, not Archive-coupled (corrected 2026-06-16 pass 3).**
  Pass 3 corrected the previous misdiagnosis ("Archive-coupled"): the 47 remaining unused items are
  ALL unused function parameters (declarationUSR format `param-<name>-<method>-<swift_mangled>`,
  confirmed by inspecting the fresh cold-scan ScanCache). Examples: `context` in `init(from:context:)`,
  `credential` in `handlePasswordCredential(_:)`, scattered across 40+ active non-Archive Swift files.
  The anchored `**/Prodcore/Archive/**` indexExclude (the 15 top-level uncompiled Archive files) has
  zero effect on these — they are independent. forceRemoveAll does NOT remove unused parameters by
  design; each requires explicit review. These are genuine findings (real unused parameters) with no
  automated removal path. The current `indexExclude` entry `**/Prodcore/Archive/**` may be removed
  from the config (it is harmless but serves no purpose for removing the 47 unused params).
  ACTION REQUIRED for unused→0: review each of the 47 unused parameters individually; either add
  `_ = param` usage, rename to `_`, or remove the parameter from the signature if truly dead.
  This is a Prodcore code-quality task, not a Treeswift/Periphery bug. The exact removal-gate
  mechanism (parameters carry `.unused` but Periphery emits a point location, so
  `hasFullRange`/`canRemoveCode` is false → `forceRemoveAll` skips them) and the safe `rename-to-_`
  fix design are documented in `docs/proposals/algorithmic-warning-fixes.md` Part 3.
  Config note: the temporary `**/Prodcore/Archive/**` indexExclude probe was REVERTED — the saved
  Prodcore config's `indexExclude` is back to `['**/*?.build/**/*', '**/SourcePackages/checkouts/**']`.
- **Regression fixtures: 0/0 — build them.** Need a `Prodcore-cleanup/fixtures/` corpus AND
  upstream Periphery tests for Issues 13/14/15 and the Codable-type-retention fix, mirroring
  `Tests/PeripheryTests/RetentionTest.swift` + `Tests/Fixtures/Sources/RetentionFixtures/`.
  Specifically the Codable fix owes a fixture extending `FixtureStruct14` with a custom-struct
  property type that would otherwise be unused.
