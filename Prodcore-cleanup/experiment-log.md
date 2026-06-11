# Git-History Convergence Experiment — Narrative Log

Human-readable companion to `experiment-state.json` (the authoritative resume state) and
`convergence-ledger.md` (the per-pass metrics). One section per baseline; one line per pass; a
verdict per baseline. Append-only.

**Goal:** check out the Prodcore commit just before each of Dan's historical dead-code cleanup
campaigns, then drive Treeswift to remove ALL unused + redundant-accessibility code until both reach
zero — proving the analysis + removal are correct. Runs fully autonomously (no check-ins); on any
problem: document, reset to `DanCleanupJune10`, advance.

Baselines (process order, newest→oldest): R5 `a1711d27` (2026-06-04), R4 `20fb9b87` (2026-05-31),
R-May `96e372e4` (2026-04-19, covers 05-04+05-12 develop-merged campaigns), R3 `23ad2547`
(2026-04-13, the biggest dirty baseline).

Convergence floor: `assignOnlyProperty` + `redundantProtocol` are non-removable by design and may
remain > 0; the loop stops on `unused==0 AND redunAcc==0`.

---

## Phase A — setup (2026-06-11)

- Prodcore clean, on home branch `DanCleanupJune10`. `Local.xcconfig` present (291 bytes).
- Treeswift on branch `june10bigtest` (home). Built clean; dylib verified FRESH (mtime
  1781159104 ≥ newest source 1781158976) at
  `…/DerivedData/Treeswift-dinllqxkmqwisdexefwnooymbqcx/Build/Products/Debug`.
- Created `experiment-state.json` + this log; added `baseline` column to the ledger.

---

## R5 — `a1711d27` (2026-06-04), precedes the 06-05 "treeswift removals" run

- Checked out throwaway branch `ts-converge-R5-a1711d27`. Pristine build (`-disableAutomaticPackageResolution`)
  = **BUILD SUCCEEDED, 0 errors** → absolute build semantics (any post-removal error is a real FP).
- **Pass 1:** scan = unused **271**, redunAcc **464**, assignOnly 5, total 740. forceRemoveAll →
  **721 deleted / 167 files** (−4894 lines). Build **clean, 0 FPs**. 5 `redundantPublicAccessibility`
  ghost modifications (F17 no-op guard) unapplied in Main/Gear/{ProductCatalogDetailView,
  ProductCategoriesView, ProductsLibraryView}. Committed `137fd70d`.
- **Pass 2:** rescan = unused **1**, redunAcc **99** (both ↓), total 105. forceRemoveAll →
  **100 deleted / 17 files**. Build **clean, 0 FPs, 0 ghosts** (the 5 pass-1 ghosts resolved once
  surrounding dead code was removed — they were stale source positions, not a removal bug).
  Committed `1f12d964`. Supervisor: **CONVERGING ✅** (unused 271→1, redunAcc 464→99, no new errors).
- **Pass 3:** rescan unused **0**, redunAcc **5** (total 10). forceRemoveAll → 5 / 3 files, builds
  clean. Committed `24a02d22`.
- **Passes 3→4 apparent stall → CACHE BUG (not a real ghost).** redunAcc held at 5 with 5 no-op
  ghosts in StatusInfo / ProgramDisplayModel / TuneTargetDisplayModels (declarations already
  narrowed). Diagnosed as **stale Treeswift ScanCache**: the 153 MB `scan-cache-<UUID>.json`
  survived in-loop `rm` (zsh glob errored after the running app rewrote it), re-serving already-fixed
  access-control warnings against stale source positions. Treeswift's cache invalidation is
  incomplete for in-place access-keyword rewrites. Killed app → deleted cache by exact name → COLD
  rescan = **unused 0, redunAcc 0, assignOnly 5.**
- **R5 CONVERGED ✅** — unused 271→0, redunAcc 464→0, **776 decls removed** across 3 passes, build
  clean every pass, **0 false positives.** Floor = 5 assignOnly (non-removable, expected).
- Finding recorded as memory `scancache-stale-accesscontrol-ghosts`: always kill app + delete the
  cache file by exact name before a convergence verdict. NOT a false positive, NOT a Periphery bug —
  a Treeswift cache-correctness bug (worth fixing separately).
- Supervisor vehicle: inline (main agent runs the measured loop + verdict).

---

## R4 — `20fb9b87` (2026-05-31), precedes the 06-01 "couple dead references" run

- Checked out `ts-converge-R4-20fb9b87` (797 swift files). **Pristine build first FAILED — code
  signing**, not compilation: "No profiles for 'app.prodcore.Prodcore'… Automatic signing disabled."
  R4 predates the 06-01 Local.xcconfig-at-root commit, so the current signing config doesn't match.
  Signing is **orthogonal to dead-code analysis** (a false positive is a COMPILE error). Re-built
  with `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO` → **BUILD SUCCEEDED, 0
  errors.** Adopted these flags for all Prodcore builds (also needed for R-May/R3).
- **Pass 1:** scan unused **272**, redunAcc **465**, assignOnly 5, total 742 (≈ R5; only days apart).
  forceRemoveAll → **723 deleted / 167 files** (−4903 lines). Build **clean, 0 FPs** (5 access-control
  cache ghosts, the known ScanCache artifact). Committed.
- **Pass 2:** unused 272→1, redunAcc 465→99. 100 / 17 files, clean, 0 ghosts. Committed `c7bd9247`.
- **Pass 3:** unused 1→0, redunAcc 99→5. 5 / 3 files, clean. Committed `4a422c93`. Then **cold-cache
  verdict** (kill app + delete cache by exact name) → **unused 0, redunAcc 0, assignOnly 5**.
- **R4 CONVERGED ✅** — unused 272→0, redunAcc 465→0, **~828 decls removed**, build clean every pass,
  **0 false positives.** Cold-cache discipline (from the R5 finding) avoided the phantom-ghost detour.

---

## R-May — `96e372e4` (2026-04-19), precedes the 05-04 + 05-12 develop-merged cleanups

Much dirtier than R5/R4 (unused 260, redunAcc **1330**, total 1593 — `redundantInternalAccessibility`
alone 1111). Pristine build clean with `CODE_SIGNING_ALLOWED=NO` + pin. Scans here are slow (~20 min,
HTTP-starved during analysis) — used a silent background waiter polling `/scan/status`.

This baseline surfaced **two genuine Treeswift removal bugs** (fixed at root, per mandate):

- **F18 — synchronized-folder `membershipExceptions` files deleted.** First `forceRemoveAll` deleted
  4 fully-dead files (ProductType, DocumentOperations, IconReference, RegionHelpers) → *"Build input
  files cannot be found."* They are pinned individually in `project.pbxproj` via a
  `PBXFileSystemSynchronizedBuildFileExceptionSet.membershipExceptions` list (modern blue-folder
  format), which `XcodeProjectFileChecker` did not parse. **Fixed**
  (`parseSynchronizedMembershipExceptions`) → those files are now shelled, not deleted. Verified: the
  4 became 1–15 line shells, "input files" error gone.
- **F19 — `public` left on extension members after type downgrade.** After F18, exactly 4 errors
  remained: *"cannot declare a public initializer in an extension with internal requirements"*
  (ProductionInspector/ProductionToolbar/FastPickerView/GridPickerView — generic types with a
  constrained-extension `public init`). Periphery downgrades the type but not its extension's
  `public init`. **Fixed** (`cascadePublicStripFromExtensions`) → strips `public` from a downgraded
  type's extension members. Isolation check: **unused-only removal was already clean** (257 deleted,
  0 errors), proving the core claim is independent of this access-control bug.
- **Driver-discipline lesson:** a scan/removal run against an already-partially-removed tree produced
  spurious "Extraneous '}'" brace-corruption errors. Root cause was MINE (contaminated tree), not
  Treeswift. After hard-resetting to pristine + cold scan, a **single** `forceRemoveAll` (F18+F19) =
  **1586 deleted / 296 files, BUILD SUCCEEDED, 0 false positives.** Rule reinforced: `git restore` to
  pristine BEFORE every scan, not just before removal.
- **Pass 1 (clean):** 1586 deleted / 296 files (−5794 lines), build clean, 0 FPs. Committed `13b225cc`.
- **Pass 2:** unused 260→8, redunAcc 1330→192. 200 / 46 files, clean, 0 ghosts. Committed `ed9292e0`.
- **Pass 3:** unused 8→1, redunAcc 192→23. 24 / 9 files, clean. Committed `0d34fbfe`.
- **Pass 4 (cold verdict):** **unused 0, redunAcc 0, assignOnly 3.**
- **R-May CONVERGED ✅** — unused 260→0, redunAcc 1330→0, **~1810 decls removed** across 3 passes,
  build clean every pass, **0 false positives** (after F18 + F19). The dirtiest baseline, fully
  converged. Floor 3 assignOnly. Two Treeswift bugs found & fixed at root (F18, F19) — the experiment
  did its job.

---

## R3 — `23ad2547` (2026-04-13), precedes the 04-14→04-17 MASSIVE cleanup (~58 commits)

Biggest, oldest baseline: unused **862**, redunAcc **1939**, total **2819**. Pristine built clean
(signing off + pin) even at the oldest checkout — no package/API drift breakage.

- **Pass 1 (split unused-first):** a full `forceRemoveAll` gave 4 access-control errors, so removed
  **unused-only** to prove the core claim in isolation: **849 deleted / 235 files, builds clean, 0
  FPs.** Committed `ad3db3b6`. (Two of the 4 full-removal errors — a `PreviewSettings` over-removal —
  were on code this pass removed, so they vanished afterward.)
- **Pass 2 (redundant-accessibility) → found F20.** After unused removal, full `forceRemoveAll` left
  exactly **1** error: `method must be declared fileprivate because its result uses a fileprivate
  type` (SequenceView:724) — top-level `struct SectionGroup` narrowed to fileprivate, but
  `func computeSectionGroups() -> [SectionGroup]` in `extension Array where …` not cascaded. **Fixed**
  (`cascadeFileprivateToReferencingFunctions`, file-wide func cascade). After the fix: **2017 deleted
  / 307 files, builds clean, 0 FPs.** Committed `8f659673`.
- F17/F19/F20 are one family: when a type's access changes, every declaration constrained by it
  (extension members, funcs returning/taking it) must change in lockstep.
- **Pass 3:** unused 8→9 (2nd-order), redunAcc 2008→1059. 1068 / 146 files, clean. Committed `00df378b`.
- **Pass 4:** unused 9→0, redunAcc 1059→30. 30 / 9 files, clean. Committed `7742d491`.
- **Pass 5 (cold verdict):** **unused 0, redunAcc 0, assignOnly 4.**
- **R3 CONVERGED ✅** — unused 862→0, redunAcc 1939→0, **~3964 decls removed** across 4 passes, build
  clean every pass, **0 false positives** (after F20; F18/F19 carried from R-May). Floor 4 assignOnly.
  The biggest/oldest baseline, fully converged.

---

## EXPERIMENT COMPLETE — all 4 baselines converged

| baseline | date | unused→0 | redunAcc→0 | decls removed | passes | floor (assignOnly) |
|----------|------|----------|-----------|---------------|--------|--------------------|
| R5 `a1711d27` | 2026-06-04 | 271→0 | 464→0 | 776 | 3 | 5 |
| R4 `20fb9b87` | 2026-05-31 | 272→0 | 465→0 | ~828 | 3 | 5 |
| R-May `96e372e4` | 2026-04-19 | 260→0 | 1330→0 | ~1810 | 3 | 3 |
| R3 `23ad2547` | 2026-04-13 | 862→0 | 1939→0 | ~3964 | 4 | 4 |

**Every baseline: unused→0, redundant-accessibility→0, build clean every pass, ZERO false positives.**
Total ~7378 dead/redundant declarations removed across the four historical baselines, all building
clean.

**Three real Treeswift removal bugs found & fixed at root** (the experiment's payoff — none were
visible at current HEAD, which was already clean; only the dirtier historical baselines exposed them):
- **F18** — files pinned in `PBXFileSystemSynchronizedBuildFileExceptionSet.membershipExceptions`
  deleted → "Build input files cannot be found." (`XcodeProjectFileChecker`)
- **F19** — `public` left on extension members after a type was downgraded → "cannot declare a public
  initializer in an extension with internal requirements." (`cascadePublicStripFromExtensions`)
- **F20** — `fileprivate` not cascaded to an extension-method/free-function result → "method must be
  declared fileprivate because its result uses a fileprivate type."
  (`cascadeFileprivateToReferencingFunctions`)
F17/F19/F20 are one family: when Treeswift changes a type's access, every declaration constrained by
that access must change in lockstep.

**Process lessons captured to memory:** ScanCache staleness for in-place access rewrites (cold-clear
by exact filename before any verdict); always `git restore` to pristine before every scan; disable
code signing for pre-06-01 baselines; pin packages with `-disableAutomaticPackageResolution`; slow
scans starve HTTP (poll `/scan/status`).
