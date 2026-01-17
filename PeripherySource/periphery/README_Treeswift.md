# Treeswift Modifications to Periphery

This document describes all local modifications made to the Periphery source code to enable deep integration with Treeswift. These modifications follow the **diff minimization strategy** from CLAUDE.md to ease future upstream merges.

## Base Version

- **Upstream**: https://github.com/peripheryapp/periphery
- **Base commit**: 4dd2a038 (clean upstream 5a4ac8b, post-3.4.0 release)
- **Current modifications**: 17 files changed, 488 insertions, 25 deletions
- **Migration**: Applied via patch from 3.2.0 baseline, manually updated for 3.4.0+ API changes

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

## Diff Minimization Patterns Used

Following CLAUDE.md guidelines to minimize diff with upstream:

### 1. Public modifiers on separate lines
```swift
// Original line preserved:
final class Project {

// Modified (appears as pure insertion):
public
final class Project {
```

### 2. Leading commas for parameter additions
```swift
// Original line preserved:
logger: Logger

// Modified (appears as pure insertion):
logger: Logger
, progressDelegate: ScanProgressDelegate? = nil
```

### 3. Multi-line boolean expressions
```swift
// Original preserved, continuation added:
lhs.file == rhs.file && lhs.line == rhs.line && lhs.column == rhs.column
&& lhs.endLine == rhs.endLine && lhs.endColumn == rhs.endColumn
```

### 4. Tree emoji markers for significant changes
- `// 🌲 MODIFIED VERSION FOR LOCAL PACKAGE USAGE`
- `// 🌲 MODIFICATION: Split Frontend into executable + library`
- `// 🌲 Scan now returns a duple`
- `// 🌲 Updated algorithm includes end location`

These markers make it easy to find Treeswift-specific changes when reviewing diffs.

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

```bash
# View all local modifications
git diff 4dd2a038 HEAD -- PeripherySource/periphery/

# Generate patch file
git diff 4dd2a038 HEAD -- PeripherySource/periphery/ > current_modifications.patch

# View statistics
git diff 4dd2a038 HEAD -- PeripherySource/periphery/ --stat
```

**Note**: Commit `4dd2a038` is the clean upstream baseline (5a4ac8b). All diffs against this commit show only Treeswift modifications, not upstream Periphery development.

## References

- Upstream Periphery: https://github.com/peripheryapp/periphery
- Main project documentation: [CLAUDE.md](../../CLAUDE.md)
- Implementation notes: [IMPLEMENTATION_NOTES.md](../../IMPLEMENTATION_NOTES.md)
- Patch application summary: [PATCH_APPLICATION_SUMMARY.md](../PATCH_APPLICATION_SUMMARY.md)

---

*Periphery base: 3.4.0+ (commit 5a4ac8b)*
*Baseline commit: 4dd2a038*
*Last updated: 2026-01-17*