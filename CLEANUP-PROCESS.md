# Cleanup Process — Exercising Treeswift to Fix a Codebase (and Itself)

**Concern C.** How to use Treeswift to gradually clean a real codebase (Prodcore) AND improve
Treeswift/Periphery along the way, with a measured loop that proves convergence. This is the
"how to run a cycle" doc. For the doc map see [`TREESWIFT-PROJECT-MAP.md`](TREESWIFT-PROJECT-MAP.md).

Related homes:
- Analysis fixes catalog → [`PERIPHERY-ANALYSIS-FIXES.md`](PERIPHERY-ANALYSIS-FIXES.md) (Concern A)
- Periphery library-integration mods → [`PeripherySource/periphery/README_Treeswift.md`](PeripherySource/periphery/README_Treeswift.md) (Concern B)
- Treeswift implementation → [`IMPLEMENTATION_NOTES.md`](IMPLEMENTATION_NOTES.md) (Concern D)
- Live metrics → `Prodcore-cleanup/convergence-ledger.md`
- Regression fixtures → `Prodcore-cleanup/fixtures/`
- Supervisor agent → `.claude/agents/cleanup-supervisor.md`

## The Two Goals (both must reach ZERO)

1. **Zero false positives.** A full `forceRemoveAll` removal of all of Prodcore, then a Prodcore
   build, must produce **zero build errors**. Every build error is a false positive — Periphery
   flagged something wrong, or Treeswift removed it wrong.
2. **Zero genuine dead code.** Repeated scan → remove → rescan drives the genuine `.unused` count
   to a stable zero (all real dead code removed; nothing real left).

**There is no "document and skip."** A false positive is a BUG to FIX. An entry in
`PERIPHERY-ANALYSIS-FIXES.md` is "closed" only when the bug is fixed AND a regression fixture proves
it stays fixed. Done = `build_errors` 0 in the ledger with no regressions.

## NEVER manually patch Prodcore source

If Treeswift's removal breaks the Prodcore build, **revert Prodcore and fix Treeswift/Periphery.**
Manually editing Prodcore to silence an error hides a false positive and corrupts the measurement.

## The Supervisor Owns Measurement

The **cleanup-supervisor** agent (`.claude/agents/cleanup-supervisor.md`) measures convergence and
prints a progress table. Invoke it at session start (baseline table), after every fix (confirm
`build_errors` went DOWN, no regression), and whenever unsure if it's real progress vs. whack-a-mole.
It reads/updates the ledger and emits a CONVERGING / FLAT / REGRESSED verdict. Let the table say it.

## Scan discipline — never overlap scans

The automation server already rejects a concurrent scan with HTTP `409 "scan already running"`
(`ScanHandler` checks `state.isScanning`), so two scans never truly run at once. The failure mode is
the *driver's*: firing `POST /scan` from inside a background wait-loop, or reading
`/results/summary` between back-to-back scans, yields stale or wrong counts that look like "the
numbers went up."

**Rule: one scan, one inline wait, read once.**
- Issue exactly one `POST /scan`, then poll `/status` until `idle` (or `/scan/wait`), THEN read
  `/results/summary` — all in a single foreground sequence.
- NEVER issue `POST /scan` from inside a `until …; do sleep; done` background task, and never run
  two such waiters concurrently.
- Clear `ScanCache/*.json` only once, immediately before the single scan — not between reads.
- If `POST /scan` returns 409, a scan is already in flight; wait for it instead of issuing another.

## The Measured Loop (each cycle)

1. **Build Treeswift AND verify the running binary is fresh.** BUILD SUCCEEDED can lie — a stale
   incremental build leaves the old `Treeswift.debug.dylib` in place and you test pre-fix code
   (this has wasted entire sessions). Verify:
   ```bash
   xcodebuild -project Treeswift.xcodeproj -scheme Treeswift build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
   DD=$(xcodebuild -project Treeswift.xcodeproj -scheme Treeswift -showBuildSettings 2>/dev/null | awk -F' = ' '/TARGET_BUILD_DIR/{print $2; exit}')
   ls -la "$DD/Treeswift.app/Contents/MacOS/Treeswift.debug.dylib"   # mtime must be newer than your edit
   ```
   If stale: `xcodebuild … clean` then rebuild. Resolve DerivedData via `-showBuildSettings`, never
   `find … | head -1` (picks a stale dir).

2. **Fresh scan.** Clear Treeswift's scan cache (else it reuses cached results and skips Periphery),
   relaunch the fresh app, scan Prodcore, record the summary.
   ```bash
   rm -f "$HOME/Library/Application Support/Treeswift/ScanCache/"*.json
   pkill -x Treeswift; sleep 1; rm -f /tmp/treeswift-control.json
   open "$DD/Treeswift.app" --args --automation-port 21663
   # poll /ready, then POST .../scan and .../scan/wait, then GET .../results/summary
   ```
   Prodcore config ID: `9E23EE49-A7B1-47BA-A5D6-DD150F7F15C7` · port `21663`.

3. **False-positive probe (the key measurement).** `forceRemoveAll` on the whole project, build
   Prodcore, capture EVERY distinct error and broken file, then **revert Prodcore**. The count of
   distinct errors is the surviving-false-positive number that must reach zero.

4. **Before writing a fix — two audits.**

   **(a) Check Periphery's OWN test suite first.** Changing Periphery's analysis asserts the
   author's code is wrong — a big claim. Search `PeripherySource/periphery/Tests/`
   (`PeripheryTests/RetentionTest.swift`, `AccessibilityTests/`,
   `Tests/Fixtures/Sources/RetentionFixtures/`) for a test covering this shape:
   - **Test asserts current behavior is correct** → either we're wrong (re-examine our usage) or the
     author's test encodes the bug. Don't change analysis until you can explain why that test is wrong.
   - **No test covers it** → genuine gap; fix justified. Add a Periphery test mirroring the pattern.
   - **Test expects retention that isn't happening** → already acknowledged; align with its intent.
   Record which tests you checked and the outcome.

   **(b) Overlap / partial-regression audit.** Many fixes cluster in the same mutators
   (`UsedDeclarationMarker.swift`, `AssignOnlyPropertyReferenceEliminator.swift`). A new fix can
   duplicate, conflict with, or partially undo an existing one. Have the supervisor audit the catalog
   (`PERIPHERY-ANALYSIS-FIXES.md`, the mutator source + `SourceGraphMutatorRunner` pipeline order) and
   return: NEW / EXTEND existing F# / CONFLICT with F#. If the symptom is already covered, that fix is
   incomplete/partially regressive — **correct or extend it**, don't add a parallel masking patch.

5. **Fix each false positive at its root.** Periphery analysis bug → fix in
   `PeripherySource/periphery/` (route per `README_Treeswift.md`). Treeswift removal bug → fix in
   Treeswift (`Treeswift/Core/Operations/`, `Treeswift/Core/ResultsTree/`). Add a **regression
   fixture**. Add/update the entry in `PERIPHERY-ANALYSIS-FIXES.md` (next F#).

6. **Re-measure (supervisor).** New ledger row; verdict must be CONVERGING with no regression.

7. **Only once `build_errors` is 0**: drive genuine `.unused` down by committing real removals
   folder-by-folder, re-measuring after each.

## Regression Fixtures

`Prodcore-cleanup/fixtures/` holds one minimal repro per fixed bug. After any change the supervisor
re-runs them. A fix is not real until its fixture passes and keeps passing. NOTE: Periphery unit
tests do not run via `swift test` in-repo (subtree integration mods break the standalone build);
the in-repo proof is the end-to-end `build_errors == 0` result. Unit tests are written for the
upstream checkout.

## Prodcore Project File Structure

Prodcore mixes **three** Xcode file-tracking styles, and Treeswift must treat each correctly when a
file goes fully dead (see `XcodeProjectFileChecker`):

- **Folder references (blue) / synchronized root groups** — Xcode scans the folder; a fully-emptied
  file is **deleted from disk**.
- **Explicit group references (yellow, `PBXFileReference`)** — the file is named in `project.pbxproj`;
  it is left as an **import-only shell**, never deleted (deleting it → "Build input files cannot be
  found").
- **Synchronized-folder membership exceptions** (`PBXFileSystemSynchronizedBuildFileExceptionSet` →
  `membershipExceptions`) — a file inside a blue folder but pinned individually in the project (e.g.
  to change target membership). Xcode requires it on disk, so it is treated **like a yellow
  reference: shelled, not deleted.** Missing this was bug **F18** — see PERIPHERY-ANALYSIS-FIXES.md.

No manual pbxproj editing needed; `isSafeToDelete` parses both `PBXFileReference` and
`membershipExceptions`.

## Removal Strategies

`forceRemoveAll` is the **measurement** worst case — surfaces every false positive. For committed
cleanup, `skipReferenced` is the safe default; `cascade` also removes referencing unused code. The
convergence target is that even `forceRemoveAll` produces zero build errors.

## Operational discipline (hard-won — read before a long run)

These cost real time on the 2026-06-11 git-history experiment; following them avoids the traps.

1. **Cold-clear the ScanCache before any convergence VERDICT.** The per-config cache
   `~/Library/Application Support/Treeswift/ScanCache/scan-cache-<CONFIG_UUID>.json` does NOT reliably
   invalidate after an **in-place access-keyword rewrite**, so already-fixed redundant-accessibility
   warnings re-serve as no-op "ghosts" against stale positions and a count looks stuck. Fix: `pkill -x
   Treeswift; sleep 2`, then delete the cache **by exact filename** (a zsh glob `rm …/*.json` silently
   fails when the running app just rewrote it), then relaunch and rescan. A flat redundant-acc count
   with no-op ghosts is a **cache-staleness suspect first**, not a Periphery/removal bug. (Treeswift
   cache-correctness bug, separate from any analysis fix.)
2. **`git restore` the target repo to PRISTINE before EVERY scan — not just before every removal.**
   Scanning a half-removed tree poisons everything: counts drift and a subsequent `forceRemoveAll`
   on top of shells throws spurious structural errors ("Extraneous '}'", "Static methods may only be
   declared on a type") that look like Treeswift bugs but are driver contamination.
3. **Big/old baselines scan slowly (~20 min) and STARVE the HTTP server** — `curl` times out (rc=28)
   though the app is alive at 40–55% CPU. Don't treat timeout as failure; poll `/scan/status` from a
   silent background waiter until `isScanning:false`, then read `/results/summary`.
4. **Converge `unused`-only FIRST, then the redundant-accessibility tail.** Removing
   `{"strategy":"forceRemoveAll","annotationFilter":["unused"]}` builds clean on every baseline and
   proves the core claim in isolation; the access-control tail then surfaces as a much smaller,
   well-defined set. (This is how F19/F20 were isolated from the unused logic.)
5. **Building OLD checkouts:** add `-disableAutomaticPackageResolution` (honor the baseline's pinned
   `Package.resolved`, neutralizing `branch=main` drift) and, for pre-2026-06-01 commits, disable
   code signing (`CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO`) — those
   predate the root `Local.xcconfig` and fail provisioning, which is orthogonal to dead-code analysis
   (a false positive is a COMPILE error, never a signing error). NEVER `git clean -fdx` (deletes the
   gitignored `Local.xcconfig`).

## Git-history replay (testing Treeswift against historical dirt)

To stress Treeswift beyond the current (clean) HEAD, replay the commits **just before** each manual
dead-code cleanup campaign — they are full of removable code. This is what found F18/F19/F20 (none
were visible at clean HEAD). The full run + resume state lives in `Prodcore-cleanup/experiment-state.json`
+ `experiment-log.md`; the method:

- **Find baselines:** on the target repo's first-parent main, a run of the cleanup author's commits
  is one campaign; the first non-author commit below it is that campaign's dirty baseline. (Some
  campaigns land via develop merges, not first-parent — check `git merge-base --is-ancestor`.)
- **Per baseline:** `git switch -C ts-converge-<id>-<hash> <hash>` (throwaway branch; never touch the
  home branch), capture the **pristine build error set** first (only *new* errors after removal are
  false positives — historical breakage is subtracted), then run the measured loop committing each
  pass, until `unused==0 AND redunAcc==0` on a cold-cache scan. Return to the home branch after.
- A found false positive is FIXED at root (+ a fixture) before continuing — same rule as the normal
  loop; the experiment is autonomous and self-paced.

- Prodcore repo: `~/code/Prodcore/` · config ID `9E23EE49-A7B1-47BA-A5D6-DD150F7F15C7` · port `21663`
- Automation API reference: [`docs/automation-api.md`](docs/automation-api.md)
