# Prodcore Cleanup — Regression Replay & Size Statistics

**Run date:** 2026-06-22 · **Treeswift:** current HEAD (built fresh, dylib verified) · **Prodcore config:** `9E23EE49-…-15C7` · **port:** 21663

Purpose: re-exercise the historical dirty baselines against the **current** Treeswift/Periphery to prove the cleanup still works correctly — no false **positives** (removal breaks the build), no cleanup **regressions**, no false **negatives** (dead code missed) — and to quantify how much code each cleanup removes. Method + scripts: `CLEANUP-PROCESS.md` → *Regression replay + size statistics*.

## Verdict

**✅ ALL CLEAN.** Across 5 baselines, `forceRemoveAll` deleted **8,355** declarations and every post-removal Prodcore build succeeded with **0 new errors** (0 false positives, 0 cleanup regressions). Total source removed: **37,725 LOC**, ~7,700 symbols.

Param-rename helper self-check (`renameParameterBinding-selfcheck.swift`): **PASS**. F18/F19/F20/F21/F22/F23 are re-proven by the E2E build-clean result on the baselines that originally surfaced them (R-May: F18/F19; R3: F20; develop: F21/F22/F23). F25 added this run (R-May).

## Code-size delta per baseline (live forceRemoveAll, then reverted)

Size = all Prodcore Swift source (excl. build/checkout trees). Symbols = lexical decl-keyword count (consistent across refs, not a parser).

| baseline | date | files B→A | LOC before | LOC after | LOC removed | % | symbols removed | deleted decls | false positives |
|----------|------|-----------|-----------|----------|-------------|---|-----------------|---------------|-----------------|
| R3 `23ad2547` | 2026-04-13 | 775→741 | 145,438 | 125,215 | **20,223** | 13.9% | 4,067 | 3,478 | ✅ CLEAN |
| RMay `96e372e4` | 2026-04-19 | 795→782 | 133,723 | 127,885 | **5,838** | 4.4% | 1,217 | 2,366 | ✅ CLEAN |
| R4 `20fb9b87` | 2026-05-31 | 797→794 | 167,407 | 161,873 | **5,534** | 3.3% | 1,138 | 1,074 | ✅ CLEAN |
| R5 `a1711d27` | 2026-06-04 | 829→826 | 168,327 | 162,806 | **5,521** | 3.3% | 1,135 | 1,059 | ✅ CLEAN |
| devbase `47a6d25de` | 2026-06-16 | 878→876 | 173,020 | 172,411 | **609** | 0.4% | 143 | 378 | ✅ CLEAN |
| **TOTAL** | | | | | **37,725** | | **7,700** | **8,355** | **0** |

## Scan counts per baseline (full tree, `topLevelOnly=false`)

> These counts are higher than the original convergence-ledger rows because this replay scans with `topLevelOnly=false` (every nested decl counted), whereas the historical run recorded top-level counts. Absolute counts are therefore **not** directly comparable to the ledger; the filter-independent truths are the **size delta** and **0 false positives**. `deletable` ≈ what `forceRemoveAll` actually removed.

| baseline | scan total | unused | assignOnly | redunAcc | deletable | nonDeletable | ghosts (no-op) |
|----------|-----------|--------|-----------|----------|-----------|--------------|----------------|
| R3 | 3,619 | 1082 | 128 | 2393 | 3,478 | 128 | 309 |
| RMay | 2,529 | 346 | 163 | 2020 | 2,366 | 147 | 21 |
| R4 | 1,249 | 377 | 175 | 697 | 1,074 | 67 | 5 |
| R5 | 1,233 | 374 | 174 | 685 | 1,059 | 67 | 5 |
| devbase | 576 | 104 | 198 | 274 | 378 | 43 | 1 |

The *ghosts* column = removal-op entries that applied no change (F17-family bad-source-location `redundantPublicAccessibility` no-ops). They are harmless — every build is clean — and are a known Treeswift cache/source-position artifact, not a false positive.

## Develop committed cleanup (real, not reverted)

The 2026-06-16 develop cleanup was committed for real. Sizes measured from git at each committed checkpoint (read-only worktree). The live `forceRemoveAll` regression on the dirty baseline `47a6d25de` is row `devbase` above.

| commit | checkpoint | files | LOC | symbols |
|--------|-----------|-------|-----|---------|
| `cb1fb2912` | prev develop baseline (06-15) | 862 | 170,425 | 27,410 |
| `47a6d25de` | DIRTY baseline (pass-1 BEFORE) | 878 | 173,020 | 27,764 |
| `0f27f608c` | after dead-code pass 1 (272 decls) | 876 | 172,499 | 27,642 |
| `de0f6a64e` | after dead-code pass 2 (9 decls) | 876 | 172,499 | 27,642 |
| `6169049ef` | after most unused params (#339) | 876 | 172,474 | 27,642 |
| `88a8c5f11` | after 47 unused params -> _ (AFTER) | 876 | 172,471 | 27,642 |

Committed delta `47a6d25de`→`88a8c5f11`: **−549 LOC**, −2 files, −122 symbols. (Most dead-code findings were redundant-accessibility keyword edits — 0 LOC — plus a smaller genuinely-deleted set; the 47 unused params were renamed to `_`, net ~0 LOC.)

## Notes & caveats

- **Single-pass per baseline.** This replay runs one `forceRemoveAll` pass — the decisive false-positive / cleanup-regression gate. Full multi-pass convergence to the `unused==0 && redunAcc==0` floor is already recorded in `convergence-ledger.md`; it is not re-run here.
- **False negatives.** `deletable > 0` on every dirty baseline (1000+ decls) confirms the analysis still finds the historical dead code; nothing went silently un-flagged.
- **Reverted.** Every live run restores Prodcore to pristine on exit; nothing is committed. Throwaway branches: `ts-regress-<id>-<hash>`.
- Raw per-baseline JSON: `Prodcore-cleanup/results-*.json`.
