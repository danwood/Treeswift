# Removal-Strategy Matrix — skipReferenced bug found & fixed (2026-06-22)

Exercised the 3 code-removal strategies across top-level Prodcore subfolders, across 3 historical
baselines (R3/R-May/R5), to verify each strategy's behaviour and folder-scope confinement.

- **Loops:** baseline × top-6 folders (by unused count) × {skipReferenced, forceRemoveAll, cascade}.
  Scan once per baseline; git-reset to pristine before every strategy run; build Prodcore after each.
- **Driver:** `strategy-matrix.sh` → `strategy-matrix-results.tsv`; summary `summarize-matrix.py`.
- **Scope confinement: perfect** — 0 cells changed any file outside the target folder, all runs.

## What the matrix found: a real `skipReferenced` bug

`skipReferenced` (the doc's "safe default") FAILED to build in 6/18 cells — and the failure was NOT a
folder-scoping artifact: **whole-project `skipReferenced` also broke the build**. Every prior
regression run (F18–F26) had only ever exercised `forceRemoveAll`, so this was never caught.

Two root causes in `UnusedDependencyAnalyzer.filterSkipReferenced`, both fixed:
1. **No fixpoint.** It decided keep/remove per-decl against the static candidate set. Keeping decl E
   (it has a live referrer) left the decls E *calls* marked for removal → E dangles. Fixed by
   iterating to a fixpoint: keep anything referenced by a decl outside the *current* remove-set,
   propagating until stable. (e.g. `processSamples`→`fastMapToVisualRange`; `toStatusInfo`→protocol
   reqs `displayName`/`color`/`systemImage`.)
2. **Cross-folder extension of a removed type.** The analyzer folds `extension <Type>` into the type
   and records the extension's source file in `referencedFiles`. A folder-scoped removal could delete
   the type while its extension's source (another folder) survived → "cannot find type". Fixed with
   `isNamedBySurvivingFile`: keep a type whose `referencedFiles` include a surviving (out-of-batch)
   file. (e.g. R3 `AffiliationDisplayModel` + its extension in `Shared/.../DisplayModelMappers.swift`.)

## Before → after (skipReferenced build outcomes)

| | pre-fix FAIL | after fixpoint | after both fixes |
|---|---|---|---|
| skipReferenced FAIL cells (of 18) | 6 | 1 | **0** |

Fixed cells: R3/Shared (7 err), R3/Engine (7), R3/Features (4), R-May/Features (2), R-May/Shared (3),
R5/CoreData (10) → all 0. No regression: every `forceRemoveAll` cell deletes the identical count
pre/post the fix. Snapshots: `strategy-matrix-results-prefix.tsv` (pre), `-fix1.tsv` (fixpoint only),
`strategy-matrix-results.tsv` (final, both fixes).

## Strategy behaviour confirmed (expected)

- **skipReferenced (opt 1):** now builds clean in every cell, whole-project and folder-scoped. Removes
  the least — the safe default, as documented.
- **forceRemoveAll (opt 2):** fails on foundational folders (Features/Shared/Core/CoreData/Units/
  Projects) — expected: it removes unused decls regardless of cross-references, which can break a
  build. Builds clean on self-contained folders (App/Engine/Main/Components/Depreciated).
- **cascade (opt 3):** still fails on the same foundational folders at FOLDER scope — it removes the
  unused referencing chain, but when that chain reaches a referrer OUTSIDE the scoped folder it cannot
  remove it, leaving a dangle. This is inherent to folder-scoped cascade (whole-project cascade has
  the full chain). OPEN QUESTION: whether folder-scoped cascade should also keep cross-scope-referenced
  types (same guard as skipReferenced) — deferred.

## Permanent gate

`regress-baseline.sh` now takes `STRATEGY=` (default forceRemoveAll). Run with
`STRATEGY=skipReferenced` to gate the safe-default strategy whole-project on every baseline — it must
build clean. Add this alongside the forceRemoveAll gate so skipReferenced never regresses unnoticed
again.
