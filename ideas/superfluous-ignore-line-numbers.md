# Investigation: Superfluous Ignore Comment Line Numbers

## Summary

Periphery currently reports the **declaration's line number** (e.g., line 33, 34) instead of the **ignore comment's line number** (e.g., line 32, 37) for superfluous ignore warnings.

**Recommendation**: This would be a **moderate-impact change**, not a minor adjustment. The effort required may not justify the benefit unless you're planning other Periphery modifications.

## Current Behavior

In `TypeWarningCache.swift`:
- Line 32: `// periphery:ignore` (actual comment)
- Line 33: `final class TypeWarningCache: Sendable {` (reported location)
- Line 37: `// periphery:ignore` (actual comment)
- Line 38: `for result in scanResults {` (reported location)

Periphery reports lines 33 and 34 because it uses the declaration's location, not the comment's location.

## Root Cause

**Declaration locations are stored, comment locations are discarded:**

1. **Comment parsing** (`PeripherySource/periphery/Sources/SyntaxAnalysis/CommentCommand.swift:6-29`):
   - Comments are parsed from syntax trivia
   - Only the command type (e.g., `.ignore`) is extracted
   - Line numbers are **not captured or stored**

2. **Declaration creation** (`PeripherySource/periphery/Sources/SyntaxAnalysis/DeclarationSyntaxVisitor.swift:333-335`):
   - Declaration location comes from `sourceLocationBuilder.location(at: position)`
   - Position is from the declaration node (e.g., `node.name.positionAfterSkippingLeadingTrivia`)
   - Comment location is never extracted from the trivia

3. **Warning generation** (`PeripherySource/periphery/Sources/PeripheryKit/ScanResultBuilder.swift:44-56`):
   - Creates `ScanResult` directly from declaration
   - Uses `declaration.location` which points to the declaration, not the comment

## Changes Required

This is **not a minor fix**. It requires modifications across multiple layers:

### 1. Store Comment Location in CommentCommand (~Low Complexity)

**File**: `PeripherySource/periphery/Sources/SyntaxAnalysis/CommentCommand.swift`

Modify the enum to store location:
```swift
enum CommentCommand: Equatable {
    case ignore(location: Location?)  // Add associated value
    // ... other cases
}
```

### 2. Extract Comment Line During Parsing (~Medium Complexity)

**File**: `PeripherySource/periphery/Sources/SyntaxAnalysis/DeclarationSyntaxVisitor.swift:357`

When parsing trivia, compute the comment's source location:
- Access to `SourceLocationConverter` is available via `sourceLocationBuilder`
- Need to determine the trivia piece's position within the source file
- SwiftSyntax trivia API provides text but not positions directly

### 3. Add Comment Location Field to Declaration (~Low Complexity)

**File**: `PeripherySource/periphery/Sources/SourceGraph/Elements/Declaration.swift:217`

Add optional field:
```swift
public var ignoreCommentLocation: Location?
```

### 4. Thread Comment Location Through Indexing (~Medium Complexity)

**File**: `PeripherySource/periphery/Sources/Indexer/SwiftIndexer.swift:370-380`

When applying comment commands in `phaseTwo()`:
- Store the comment location in the declaration
- Currently only sets `ignoredDeclarations` set

### 5. Update ScanResultBuilder (~Low Complexity)

**File**: `PeripherySource/periphery/Sources/PeripheryKit/ScanResultBuilder.swift:44-56`

Use comment location instead of declaration location:
```swift
let annotatedSuperfluousIgnoreCommands: [ScanResult] = superfluousDeclarations
    .map {
        let location = $0.ignoreCommentLocation ?? $0.location
        .init(declaration: $0, annotation: .superfluousIgnoreCommand, customLocation: location)
    }
```

### 6. Handle Parameter Ignores (~Medium Complexity)

**File**: `PeripherySource/periphery/Sources/PeripheryKit/ScanResultBuilder.swift:107-128`

Function `findSuperfluousParameterIgnores()`:
- Currently creates synthetic declarations with function location
- Would need to find parameter ignore comment location
- More complex because parameter ignores are inline with parameters

## Effort Estimate

**Total Complexity**: Medium to Medium-High

- **6 files to modify** across different subsystems
- **SwiftSyntax trivia handling** may be tricky (getting positions from trivia)
- **Testing required** across different ignore comment scenarios:
  - Function ignores
  - Type ignores
  - Parameter ignores
  - Multi-line spacing variations
- **Periphery's existing test suite** would need updates

**Estimated effort**: 4-8 hours including testing

## Recommendation

**Only proceed if:**
1. You're already planning other Periphery modifications (avoid one-off changes)
2. The incorrect line numbers are causing significant UX issues in Treeswift
3. You're comfortable maintaining this change across Periphery updates

**Alternative approach:**
- Document this as a known limitation in Treeswift UI
- Show both the comment location (estimated as declaration line - 1) and actual declaration line
- Wait to see if upstream Periphery addresses this

## Files That Would Be Modified

All in `PeripherySource/periphery/`:
1. `Sources/SyntaxAnalysis/CommentCommand.swift`
2. `Sources/SyntaxAnalysis/DeclarationSyntaxVisitor.swift`
3. `Sources/SourceGraph/Elements/Declaration.swift`
4. `Sources/Indexer/SwiftIndexer.swift`
5. `Sources/PeripheryKit/ScanResultBuilder.swift`
6. Related test files in `Tests/`

All changes would need documentation in `PeripherySource/periphery/README_Treeswift.md` per project guidelines.
