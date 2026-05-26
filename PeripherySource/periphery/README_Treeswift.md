# Treeswift Modifications to Periphery

This is the **SINGLE SOURCE OF TRUTH** for all information about Treeswift's local modifications to the Periphery package. This document describes all changes, the diff minimization strategy, and the update workflow.

## Base Version

- **Upstream**: https://github.com/danwood/periphery (branch: combine-master-redundant-nested-1062)
- **Current modifications**: 17 files changed, 488 insertions, 25 deletions

**What's in the combine-master-redundant-nested-1062 branch:**
- All changes from upstream peripheryapp/periphery `master`
- Redundant internal/fileprivate accessibility markers (`master` branch in danwood/periphery)
- Redundant nested access detection (`redundant-nested` branch in danwood/periphery)
- Fix to issue 1062 (`fix-1062` branch in danwood/periphery)

## Repository Layout (danwood/periphery)

The `danwood/periphery` repo at `/Users/dwood/code/periphery-dan-private` has these branches:

| Branch | Description |
|--------|-------------|
| `master` | Redundant internal/fileprivate accessibility markers. Rebased onto `upstream/master` after each upstream update. Many commits of development. |
| `redundant-nested` | Redundant nested access detection. Rebased onto `master` after each upstream update. |
| `fix-1062` | Fix for Periphery issue 1062. Rebased onto `upstream/master` after each upstream update. |
| `combine-master-redundant-nested-1062` | **The destination branch.** Merges all three above. This is what Treeswift tracks as subtree upstream. |
| `upstream` | Tracks peripheryapp/periphery upstream master. |

**Branch ancestry**: `master` and `fix-1062` both rebase directly onto `upstream/master`. `redundant-nested` rebases onto `master`. `combine-master-redundant-nested-1062` is built by branching from `redundant-nested` tip and merging `fix-1062` with `--no-ff`.

### Branch Diagram (ASCII)

```
peripheryapp/periphery upstream/master
       │
  upstream/master tip
       │
       ├──────────────────────────────┐
       │                              │
       ▼                              ▼
    master                         fix-1062
 (redundant internal/            (issue 1062 fix,
  fileprivate markers,            2 commits)
  many commits)                       │
       │                              │
       ▼ (redundant-nested            │
          commits rebased             │
          on top of master)           │
  redundant-nested tip                │
       │                              │
       └──────────── merge ───────────┘
                        │
                        ▼
        combine-master-redundant-nested-1062
                        │
                        │  git subtree pull (from Treeswift)
                        ▼
         Treeswift / PeripherySource/periphery/
         + Treeswift-specific commits on top:
           public APIs, progress delegate,
           end-position tracking, etc.
```

### How `combine-master-redundant-nested-1062` Was Built

The construction order matters when rebuilding after an upstream update:

1. Start from `master` tip (redundant internal/fileprivate feature)
2. Cherry-pick or rebase `redundant-nested` commits on top of `master`
3. Merge `fix-1062` branch into the result
4. The merged result becomes the new `combine-master-redundant-nested-1062` tip

**Why this order**: `redundant-nested` builds on the accessibility marker infrastructure in `master`, so it must come after. `fix-1062` is independent and can be merged in last.

## What Belongs Here vs. Upstream

**Only Treeswift-specific integration changes** should be applied directly to this subtree. These are changes required for Periphery to work as a library consumed by the Treeswift GUI — exposing public APIs, adding progress delegates, end-position tracking, etc.

**General Periphery analysis changes** (new scan rules, bug fixes in mutators, new detection patterns) must NOT be applied here. They belong in the upstream repository (danwood/periphery) and should be pulled into Treeswift via `git subtree pull`. If a task requires such a change, stop and make a plan to apply it to the correct upstream branch first.

## Modification Categories

### 1. Package Structure Changes (CRITICAL)

#### `Package.swift` (+33 lines)

**Purpose**: Expose internal modules as library products for external consumption.

**Changes**:
1. Added header comment explaining modifications (lines 4-7)
2. Split `Frontend` executable target into two targets:
   - `Frontend` (executable) - Contains only `main.swift`
   - `FrontendLib` (library) - Contains all other Frontend code
3. Added 10 new library product exports:
   - Configuration
   - SourceGraph
   - Shared
   - Logger
   - Extensions
   - Indexer
   - ProjectDrivers
   - SyntaxAnalysis
   - XcodeSupport
   - FrontendLib

**Diff minimization patterns used**:
- Leading comma on new line: `, path: "Sources/Frontend",` (line 42)
- Leading comma on exclude: `, exclude: ["main.swift"]` (line 43)

**Critical**: This file MUST be re-applied after any upstream update.

---

### 2. Location End-Position Tracking (~34 lines across 3 files)

**Purpose**: Track full source range of declarations (start AND end positions) for better UI presentation.

#### `Sources/SourceGraph/Elements/Location.swift` (+13 lines)

**Changes**:
1. Added `endLine: Int?` and `endColumn: Int?` properties
2. Updated `init` to accept optional end position parameters
3. Updated `hashValueCache` calculation to include end positions (lines 565-566)
   - Uses leading comma pattern: `, endLine, endColumn]`
4. Updated `relativeTo()` to preserve end positions (lines 574-575)
   - Uses leading comma pattern: `, endLine: endLine, endColumn: endColumn)`
5. Updated `buildDescription()` to include end position in string (lines 583-588)
6. Updated equality comparison to include end positions (lines 595-596)
   - Uses multi-line boolean pattern: `&& lhs.endLine == rhs.endLine && lhs.endColumn == rhs.endColumn`
7. Added `@unchecked Sendable` conformance for Swift 6 concurrency

**Diff minimization**: All additions appear as pure insertions, original lines preserved byte-for-byte.

#### `Sources/SyntaxAnalysis/SourceLocationBuilder.swift` (+10 lines)

**Changes**:
1. Added new `location(from:to:)` method to calculate location with end position
2. Extracts start and end positions from syntax nodes
3. Returns Location with all four coordinates

**Critical**: Required for end-position tracking functionality.

#### `Sources/PeripheryKit/Results/OutputFormatter.swift` (+7 lines)

**Changes**:
1. Updated `locationDescription()` to format end positions
2. Changed from single-expression to multi-line implementation
3. Appends `endLine` and `endColumn` to output if present

**Diff minimization**: Added comment `// 🌲 Updated algorithm includes end location`

---

### 3. Scan Progress Delegation (~35 lines across 5 files)

**Purpose**: Provide progress callbacks to GUI without relying on logger output.

#### `Sources/Shared/ScanProgressDelegate.swift` (NEW FILE, +8 lines)

**New protocol defining lifecycle callbacks**:
```swift
public protocol ScanProgressDelegate: AnyObject {
    func didStartInspecting()
    func didStartBuilding(scheme: String)
    func didStartIndexing()
    func didStartAnalyzing()
}
```

**Critical**: Entire new file, must be preserved in updates.

#### `Sources/Frontend/Project.swift` (+7 lines)

**Changes**:
1. Added `public` modifiers on separate lines (diff minimization pattern)
2. Added `progressDelegate` parameter to both init methods
3. Uses leading comma pattern: `, progressDelegate: ScanProgressDelegate? = nil`
4. Calls `progressDelegate?.didStartInspecting()` in convenience init
5. Passes delegate to XcodeProjectDriver

**Diff minimization**: Public modifiers on separate lines (lines 103, 105, 113, 133, 148).

#### `Sources/Frontend/Scan.swift` (+5 lines)

**Changes**:
1. Made class `public` (separate line, line 168)
2. Added `progressDelegate` parameter to init (leading comma pattern, lines 178-179)
3. Changed return type to `([ScanResult], SourceGraph)` tuple (line 188)
4. Added `progressDelegate?.didStartIndexing()` call (line 213)
5. Added `progressDelegate?.didStartAnalyzing()` call (line 230)
6. Return tuple instead of array (line 197)
7. Removed console output statements (replaced with delegate calls)

**Diff minimization**:
- Public modifier on separate line (line 168)
- Leading comma for parameter (line 178)

**Critical**: Return type change affects all callers.

#### `Sources/ProjectDrivers/XcodeProjectDriver.swift` (+11 lines, -12 deletions)

**Changes**:
1. Added `progressDelegate` property and parameters (leading comma pattern)
2. Removed "Inspecting project..." console output (replaced with delegate)
3. Removed "Building \(scheme)..." console output (replaced with `progressDelegate?.didStartBuilding(scheme:)`)
4. Added `excludeTests` parameter to `xcodebuild.build()` call
5. Fixed test target name handling: convert spaces to underscores (lines 485-486, 496-500)
6. Added `targetNameToModuleName()` helper method

**Diff minimization**: Leading commas throughout.

#### `Sources/Frontend/Commands/ScanCommand.swift` (+1 line)

**Changes**:
1. Updated to destructure tuple return: `let (results, graph) = try Scan(...).perform(project)`

---

### 4. Swift Concurrency Support (~9 lines across 4 files)

**Purpose**: Add task cancellation checkpoints for responsive cancellation.

#### Files modified:
- `Sources/Frontend/Scan.swift` (+4 lines) - Checkpoints in build, index, analyze, buildResults
- `Sources/Indexer/IndexPipeline.swift` (+5 lines) - Checkpoints before each indexer
- `Sources/Indexer/JobPool.swift` (+2 lines) - Checkpoints in concurrent job loops
- `Sources/SourceGraph/SourceGraphMutatorRunner.swift` (+1 line) - Checkpoint in mutator loop

**All changes**: `try Task.checkCancellation()` added at strategic points.

---

### 5. Public API Changes (~6 lines across 2 files)

**Purpose**: Make internal classes and types accessible to external packages.

#### `Sources/PeripheryKit/ScanResult.swift` (+3 lines)

**Changes**:
1. Made `Annotation` enum public (line 396)
2. Made `declaration` property public (line 404)
3. Made `annotation` property public (line 406)

**Diff minimization**: `public` keyword on separate line before each declaration.

#### `Sources/SourceGraph/Elements/Declaration.swift` (+2 lines)

**Changes**:
1. Added `@unchecked Sendable` conformance (line 525)
2. Changed `location` from `let` to `var` (line 534) - Required for updating end positions post-creation

**Note**: FIXME comment added - can we avoid making location mutable?

---

### 6. Other Enhancements (~4 lines across 3 files)

#### `Sources/Extensions/FilePath+Extension.swift` (+6 lines)

**Purpose**: Enable sorting FilePath collections.

**Changes**: Added `Comparable` conformance with lexical string comparison.

#### `Sources/XcodeSupport/Xcodebuild.swift` (+2 lines)

**Purpose**: Support excludeTests configuration option.

**Changes**:
1. Added `excludeTests` parameter to `build()` method
2. Use `build` action when excluding tests, `build-for-testing` otherwise

#### `Sources/Indexer/SourceFileCollector.swift` (-1 line)

**Purpose**: Remove unused import.

**Changes**: Removed `import FilenameMatcher` (no longer used)

#### `Sources/XcodeSupport/XcodeProject.swift` (+1 line, -1 line)

**Purpose**: Gracefully handle unresolvable file element paths.

**Changes**: Changed `try` to `try?` on `fullPath(sourceRoot:)` call when searching for sub-project references. Some project file elements have broken parent chains (e.g., orphaned references, package dependency artifacts) that cause `PBXProjError.invalidGroupPath` to be thrown. Using `try?` lets `compactMap` skip these unresolvable elements instead of crashing the scan.

#### `Sources/XcodeSupport/XcodeTarget.swift` (+2 lines, -2 lines)

**Purpose**: Gracefully handle unresolvable file element paths.

**Changes**: Changed `try` to `try?` on two `fullPath(sourceRoot:)` calls — one for file system synchronized root groups and one for build phase file references. Same rationale as XcodeProject.swift above.

---

### 7. Syntax Analysis End-Position Extraction (+23 lines)

#### `Sources/SyntaxAnalysis/DeclarationSyntaxVisitor.swift`

**Purpose**: Extract end positions from Swift syntax nodes.

**Changes**: Added `, endPosition: node.endPosition` parameter to all 22 `result()` calls across visit methods:
- visitClassDeclaration
- visitActorDeclaration
- visitExtensionDeclaration
- visitStructDeclaration
- visitEnumDeclaration (including case elements)
- visitProtocolDeclaration
- visitFunctionDeclaration
- visitInitializerDeclaration
- visitDeinitializerDeclaration
- visitSubscriptDeclaration
- visitVariableDeclaration (all binding types)
- visitTypeAliasDeclaration
- visitAssociatedTypeDeclaration
- visitOperatorDeclaration
- visitPrecedenceGroupDeclaration

Updated `result()` method signature to accept optional `endPosition` parameter (lines 763-765).

**Diff minimization**: Leading comma on new line before endPosition parameter.

#### `Sources/Indexer/SwiftIndexer.swift` (+16 lines)

**Purpose**: Apply end positions captured from syntax to Declaration objects.

**Changes**:
1. Updated location lookup to match by start position only (lines 332-342)
   - Uses `first { ... }` instead of direct dictionary lookup
   - Ignores end positions when finding matching declaration
2. Update Declaration.location with end positions if available (lines 348-359)

**Note**: FIXME comment - can this be done atomically so location can remain `let`?

---

### 8. Cache Serialization API (+4 lines across 2 files)

**Purpose**: Expose types needed for Treeswift's scan cache serialization, so the full SourceGraph and ScanResults can be reconstructed from disk.

#### `Sources/SourceGraph/Elements/DeclarationAttribute.swift` (+1 line)

**Change**: Made `name` property `public` (was `internal`):
```swift
public let name: String
```

#### `Sources/PeripheryKit/ScanResult.swift` (+4 lines)

**Change**: Added explicit `public init` (Swift auto-generates only an `internal` memberwise init for `public struct`):
```swift
public init(declaration: Declaration, annotation: Annotation) {
    self.declaration = declaration
    self.annotation = annotation
}
```

---

### 9. Observable Macro Property Type Retainer (+2 files)

#### `Sources/SourceGraph/Mutators/ObservableMacroRetainer.swift` (NEW FILE)

**Purpose**: Prevent false-positive "unused" reports for types used as property types in `@Observable`-annotated classes/structs.

**Root cause**: Periphery skips `.unit` dependencies in `SwiftIndexer.phaseOne()`, so references inside `@Observable` macro expansion files (`@__swiftmacro_*.swift`) are never indexed. Types used as property types in `@Observable` types appear unreferenced even though they're used in the macro-synthesized accessor code.

**Fix**: A `SourceGraphMutator` that finds all `@Observable`-annotated class/struct declarations, inspects their `varInstance` children's `declaredType` strings, extracts bare type names, and marks matching declarations as retained.

#### `Sources/SourceGraph/SourceGraphMutatorRunner.swift` (+1 line)

**Change**: Registered `ObservableMacroRetainer.self` in the mutator list after `AppIntentsRetainer`.

**Note**: This is a Treeswift-specific workaround for a Periphery analysis gap. Ideally the fix belongs upstream by making `SwiftIndexer.phaseOne()` process `.unit` dependencies (macro expansion records) to collect references. Document in PeripheryIssues.md.

---

## Critical Files for Future Updates

Files that MUST preserve modifications:
- ✅ `Package.swift` - Library product exports
- ✅ `Sources/Frontend/Project.swift` - Public API, progress delegate
- ✅ `Sources/Frontend/Scan.swift` - Public API, tuple return, progress delegate
- ✅ `Sources/Shared/ScanProgressDelegate.swift` - Entire new file
- ✅ `Sources/SourceGraph/Elements/Location.swift` - End position properties
- ✅ `Sources/SourceGraph/Elements/DeclarationAttribute.swift` - `name` is public
- ✅ `Sources/PeripheryKit/ScanResult.swift` - public init
- ✅ `Sources/SourceGraph/Mutators/ObservableMacroRetainer.swift` - Entire new file
- ✅ `Sources/SourceGraph/SourceGraphMutatorRunner.swift` - ObservableMacroRetainer registration

Files likely to conflict on update:
- ⚠️ `Sources/ProjectDrivers/XcodeProjectDriver.swift` - Build process changes
- ⚠️ `Sources/Indexer/SwiftIndexer.swift` - Location lookup logic
- ⚠️ `Sources/SyntaxAnalysis/DeclarationSyntaxVisitor.swift` - Many small additions

---

---

## Why Use a Local Modified Package?

The upstream Periphery Swift Package exposes only `PeripheryKit` as a library product. The internal scanning orchestration logic (`Scan`, `Project`, `ProjectDriver` implementations, etc.) is part of the `periphery` executable target and cannot be imported as libraries.

By maintaining a local modified copy of the package, we can:
- Expose additional library products (Configuration, SourceGraph, FrontendLib, etc.)
- Make internal classes public where needed (`Project`, `Scan`)
- Maintain our own modifications while staying synchronized with upstream
- Use the standard Swift Package Manager module system

---

## Git Subtree Management

The `PeripherySource/periphery` directory is managed as a **git subtree** tracking danwood/periphery changes.

**Current Setup (Treeswift repo remotes):**
```bash
# These remotes are already configured in the Treeswift repo
# danwood-fork  → https://github.com/danwood/periphery   (current source)
# periphery-upstream → https://github.com/peripheryapp/periphery.git
```

---

### Pulling Latest from danwood/periphery (normal update)

Use this when new commits have been pushed to `combine-master-redundant-nested-1062` in `periphery-dan-private`:

```bash
# Run from the Treeswift repo root
git fetch danwood-fork
git subtree pull --prefix=PeripherySource/periphery danwood-fork combine-master-redundant-nested-1062 --squash
```

If there are conflicts (see below), resolve them, then:

```bash
git add PeripherySource/periphery/
git commit -m "Update subtree to latest danwood/periphery combine-master-redundant-nested-1062"
```

---

### Pulling Latest from peripheryapp/periphery Upstream

Use this when you want to absorb new upstream Periphery releases into the danwood/periphery branches. **This is a two-phase process** — first update `periphery-dan-private`, then pull into Treeswift.

#### Phase 1 — Update danwood/periphery branches (in `periphery-dan-private`)

Use the automated script — it handles all rebases, conflict detection, and force-pushing:

```bash
cd /Users/dwood/code/periphery-dan-private
./update-from-upstream.sh
```

**What the script does (5 steps):**

1. **fetch** — `git fetch upstream`
2. **rebase-master** — Rebase `master` onto `upstream/master`
3. **rebase-fix-1062** — Rebase `fix-1062` onto `upstream/master`
4. **rebase-rn** — Rebase `redundant-nested` onto `master`
5. **combine** — Recreate `combine-master-redundant-nested-1062` by branching from `redundant-nested` tip and merging `fix-1062` with `--no-ff`

Then force-pushes all four branches to `origin`.

**If the script pauses on a conflict**, it prints instructions. After resolving:

```bash
git add <resolved-files>
git rebase --continue   # (or git merge --continue for the combine step)
./update-from-upstream.sh --resume <STEP_NAME>
```

Step names for `--resume`: `fetch`, `rebase-master`, `rebase-fix-1062`, `rebase-rn`, `combine`

**Before running**, check what's new upstream:

```bash
git fetch upstream
git log --oneline upstream/master ^master   # commits in upstream not yet in master
```

#### Phase 2 — Pull into Treeswift (in Treeswift repo)

```bash
git fetch danwood-fork
git subtree pull --prefix=PeripherySource/periphery danwood-fork combine-master-redundant-nested-1062 --squash
# Resolve conflicts (see below), then commit
```

---

### Resolving Conflicts

These files are most likely to conflict when pulling upstream changes:

| File | Why | Resolution strategy |
|------|-----|---------------------|
| `Sources/ProjectDrivers/XcodeProjectDriver.swift` | We add `progressDelegate`, `excludeTests`, target name fixes | Keep our additions; take upstream changes to surrounding logic |
| `Sources/Indexer/SwiftIndexer.swift` | We change location lookup to match by start-pos only | Keep our `first { }` lookup block; integrate upstream changes around it |
| `Sources/SyntaxAnalysis/DeclarationSyntaxVisitor.swift` | We add `, endPosition:` to all 22 `result()` calls | Re-apply our leading-comma insertions after upstream changes; use `git diff` to confirm all `result()` calls still have `endPosition` |
| `Sources/Frontend/Scan.swift` | We change return type to tuple, add delegate calls | Keep tuple return and delegate calls; integrate upstream logic changes |
| `Package.swift` | We split Frontend into executable+library, add 10 products | Always keep our version entirely; upstream Package.swift changes rarely affect our added targets |

**General conflict rule**: our modifications are almost always pure additions (new parameters, new files, new methods). When in doubt, keep our additions and take upstream's changes to the surrounding code.

**After resolving any conflict file:**
```bash
# Verify 🌲 markers are all still present
grep -r "🌲" PeripherySource/periphery/Sources/

# Verify new files still exist
ls PeripherySource/periphery/Sources/Shared/ScanProgressDelegate.swift
ls PeripherySource/periphery/Sources/SourceGraph/Mutators/ObservableMacroRetainer.swift
```

---

### Verifying Modifications After Any Update

```bash
# View all Treeswift modifications against danwood fork baseline
git diff danwood-fork/combine-master-redundant-nested-1062 HEAD -- PeripherySource/periphery/

# Count changed lines (expect ~17 files, ~488 insertions, ~25 deletions)
git diff --stat danwood-fork/combine-master-redundant-nested-1062 HEAD -- PeripherySource/periphery/
```

---

## Diff Minimization Strategy

**Goal:** Minimize diff with upstream to ease future updates.

**Rule:** Preserve original lines byte-for-byte. Make additions appear as pure insertions (+ lines), not modifications (+/- lines).

This strategy makes our modifications easier to maintain across upstream updates because:
- Git can better auto-merge changes when original lines are untouched
- Patch files are more resilient to upstream refactoring
- Diffs are cleaner and easier to review
- Re-applying modifications after conflicts is simpler

### Diff Minimization Patterns

#### 1. Adding to start of line - split across lines

**Pattern:** Place modifier on separate line before original line
```swift
// Bad (modifies existing line):
public final class Project {

// Good (pure insertion):
public
final class Project {
```

#### 2. Adding to end of line - use leading comma on new line

**Pattern:** Keep original line intact, add continuation with leading comma
```swift
// Bad (modifies existing line):
logger: Logger, progressDelegate: ScanProgressDelegate? = nil

// Good (pure insertion):
logger: Logger
, progressDelegate: ScanProgressDelegate? = nil
```

#### 3. Adding to boolean expressions - continue on new line

**Pattern:** Keep original expression intact, continue condition on new line
```swift
// Good (original line preserved):
lhs.file == rhs.file && lhs.line == rhs.line && lhs.column == rhs.column
&& lhs.endLine == rhs.endLine && lhs.endColumn == rhs.endColumn
```

#### 4. Tree emoji markers for significant changes

**Pattern:** Use 🌲 emoji in comments to mark Treeswift-specific modifications
```swift
// 🌲 MODIFIED VERSION FOR LOCAL PACKAGE USAGE
// 🌲 MODIFICATION: Split Frontend into executable + library
// 🌲 Scan now returns a duple
// 🌲 Updated algorithm includes end location
```

These markers make it easy to identify Treeswift-specific changes when reviewing diffs.

**Verification command:**
```bash
# Run from Treeswift repo root — should show only Treeswift-specific additions, minimal line modifications
git diff danwood-fork/combine-master-redundant-nested-1062 HEAD -- PeripherySource/periphery/
```

This should show minimal modifications to existing lines.

## References

- Upstream Periphery: https://github.com/peripheryapp/periphery
- Main project documentation: [CLAUDE.md](../../CLAUDE.md)
- Implementation notes: [IMPLEMENTATION_NOTES.md](../../IMPLEMENTATION_NOTES.md)
- Patch application summary: [PATCH_APPLICATION_SUMMARY.md](../PATCH_APPLICATION_SUMMARY.md)

---

*Last updated: 2026-05-26*