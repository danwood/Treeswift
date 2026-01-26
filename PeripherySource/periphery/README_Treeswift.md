# Treeswift Modifications to Periphery

This is the **SINGLE SOURCE OF TRUTH** for all information about Treeswift's local modifications to the Periphery package. This document describes all changes, the diff minimization strategy, and the update workflow.

## Base Version

- **Upstream**: https://github.com/danwood/periphery (branch: redundant-nested)
- **Base commit**: 8ebf4a42 (includes post-3.4.0 + additional fixes)
- **Previous upstream**: https://github.com/peripheryapp/periphery (commit 5a4ac8b)
- **Current modifications**: 17 files changed, 488 insertions, 25 deletions
- **Migration**: Switched from peripheryapp/periphery to danwood/periphery redundant-nested branch

**What's in the redundant-nested branch:**
- All changes from upstream periphery post-3.4.0
- #Preview macro unused code detection (unless --retain-swift-ui-previews)
- Redundant nested access detection
- Redundant internal/fileprivate accessibility markers
- Accessibility warning fixes and CI improvements

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

## Critical Files for Future Updates

Files that MUST preserve modifications:
- ✅ `Package.swift` - Library product exports
- ✅ `Sources/Frontend/Project.swift` - Public API, progress delegate
- ✅ `Sources/Frontend/Scan.swift` - Public API, tuple return, progress delegate
- ✅ `Sources/Shared/ScanProgressDelegate.swift` - Entire new file
- ✅ `Sources/SourceGraph/Elements/Location.swift` - End position properties

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

**Current Setup:**
```bash
# Configured remotes
git remote add periphery-upstream https://github.com/peripheryapp/periphery.git  # Original upstream
git remote add danwood-fork https://github.com/danwood/periphery                 # Current source

# Current baseline: 8ebf4a42 from danwood/periphery redundant-nested branch
```

**To update to the latest redundant-nested branch:**

```bash
# Pull the latest redundant-nested branch from danwood fork
git fetch danwood-fork redundant-nested
git subtree pull --prefix=PeripherySource/periphery danwood-fork redundant-nested --squash

# After the merge, verify local modifications are still present
# Resolve any conflicts, prioritizing Treeswift modifications

# Stage changes
git add PeripherySource/periphery/
git commit -m "Update subtree to latest danwood/periphery redundant-nested"
```

**To switch back to upstream peripheryapp/periphery:**

```bash
# Pull from the original upstream
git subtree pull --prefix=PeripherySource/periphery periphery-upstream master --squash

# After the merge, verify and re-apply local modifications if needed
git add PeripherySource/periphery/
git commit -m "Switch subtree back to peripheryapp/periphery upstream"
```

**Git subtree workflow:**
- The `danwood-fork` remote currently points to `https://github.com/danwood/periphery`
- The `periphery-upstream` remote still points to `https://github.com/peripheryapp/periphery`
- Updates are pulled with `git subtree pull` and squashed into a single commit
- Treeswift modifications are preserved in separate commits on top
- When merging new upstream versions, git will attempt to preserve your changes
- If conflicts occur, resolve them prioritizing Treeswift modifications

**Benefits of git subtree:**
- Keeps the complete periphery source code in your repository
- Tracks upstream changes and allows easy updates
- Preserves your local modifications in git history
- No need for separate submodule checkouts
- Simple merge workflow for pulling upstream changes
- The local package can be referenced directly in Xcode

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
git diff 4dd2a038 HEAD -- PeripherySource/periphery/
```

This should show minimal modifications to existing lines.

---

## Update Workflow

When updating to a newer Periphery version:

1. **Create baseline**: Replace PeripherySource/periphery/ with clean upstream code (creates new baseline commit like 4dd2a038)
2. **Generate patch**: Run `git diff <old-baseline> <old-modified> -- PeripherySource/periphery/ > periphery_modifications.patch`
3. **Apply patch**: Use `git apply` or `patch` to apply modifications to new baseline
4. **Manual fixes**: Resolve any .rej files from failed patch hunks (API changes, moved files, etc.)
5. **Test thoroughly**: Ensure Treeswift builds and scans work correctly
6. **Update this README**: Document any new modifications or changes to existing ones
7. **Commit**: Create commit with modifications applied

## Viewing Current Modifications

To see all Treeswift modifications to Periphery (excluding upstream changes):
redundant-nested
```bash
# View all local modifications against danwood fork baseline
git diff danwood-fork/redundant-nested HEAD -- PeripherySource/periphery/

# Generate patch file
git diff danwood-fork/redundant-nested HEAD -- PeripherySource/periphery/ > current_modifications.patch

# View statistics
git diff --stat danwood-fork/redundant-nested HEAD -- PeripherySource/periphery/
```

**Note**: The current baseline is commit `8ebf4a42` from danwood/periphery redundant-nested branch. All diffs against this show only Treeswift modifications, not danwood fork changes.

## References

- Upstream Periphery: https://github.com/peripheryapp/periphery
- Main project documentation: [CLAUDE.md](../../CLAUDE.md)
- Implementation notes: [IMPLEMENTATION_NOTES.md](../../IMPLEMENTATION_NOTES.md)
- Patch application summary: [PATCH_APPLICATION_SUMMARY.md](../PATCH_APPLICATION_SUMMARY.md)

---

*Periphery base: 3.4.0+ (commit 5a4ac8b)*
*Baseline commit: 4dd2a038*
*Last updated: 2026-01-17*