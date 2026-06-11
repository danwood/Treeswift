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

Prodcore mixes folder references (blue) and explicit group references (yellow). Treeswift detects
each: folder-reference files are deleted from disk when empty; explicit-reference files are left as
import-only shells. No manual pbxproj editing needed.

## Removal Strategies

`forceRemoveAll` is the **measurement** worst case — surfaces every false positive. For committed
cleanup, `skipReferenced` is the safe default; `cascade` also removes referencing unused code. The
convergence target is that even `forceRemoveAll` produces zero build errors.

- Prodcore repo: `~/code/Prodcore/` · config ID `9E23EE49-A7B1-47BA-A5D6-DD150F7F15C7` · port `21663`
- Automation API reference: [`docs/automation-api.md`](docs/automation-api.md)
