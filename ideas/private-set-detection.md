# Feature Idea: Detect Properties That Could Be `private(set)`

## Summary

Periphery does not currently detect properties whose setters are never called externally and could therefore be narrowed to `private(set)`. This would be a new analysis capability requiring changes to Periphery's reference tracking model.

## Current State

### What Periphery *does* detect regarding `private(set)`

Periphery's `RedundantAccessibilityMarker` can detect when a `private(set)` modifier is **redundant** — i.e., it matches what's already implied by the enclosing type's access level. For example:

- `fileprivate(set) var foo` inside a `fileprivate class` — the setter modifier is redundant
- `internal(set) var foo` inside an `internal class` — same situation

These produce the existing `redundantAccessibility` annotation.

### What Periphery *cannot* detect

- Properties that are never **mutated** externally (only read from outside the declaring type)
- Properties that should become `private(set)` because external code only uses the getter
- Any distinction between read vs. write references to a declaration

### Relevant code locations

- **Annotation types**: `PeripherySource/periphery/Sources/PeripheryKit/ScanResult.swift` (lines 6–15)
- **Redundant accessibility logic**: `PeripherySource/periphery/Sources/SourceGraph/Mutators/RedundantAccessibilityMarker.swift` (lines 70–103)
- **Test fixtures**: `PeripherySource/periphery/Tests/AccessibilityTests/AccessibilityProject/Sources/TargetA/RedundantAccessibilityComponents.swift`

## Why This Doesn't Exist Yet

Periphery's `SourceGraph` tracks that declarations are **referenced**, but does not distinguish between **read** and **write** references. To detect `private(set)` candidates, the tool would need to know that a property's setter is never invoked from outside its declaring scope while the getter is.

## What Would Be Required

### 1. Capture reference kind from the indexer

SourceKit's index data includes a `kind` for each reference occurrence. Property reads and writes produce different USR reference kinds (e.g., `getter` vs. `setter` accessor references, or `read` vs. `write` for stored properties). Periphery's `SwiftIndexer` would need to capture and store this distinction.

**Files**: `PeripherySource/periphery/Sources/Indexer/SwiftIndexer.swift`, potentially `IndexStoreIndexer.swift`

### 2. Extend the Reference model

The `Reference` type would need a field indicating whether it's a read or write (or both, for `+=` style mutations).

**File**: `PeripherySource/periphery/Sources/SourceGraph/Elements/Reference.swift`

### 3. New mutator/analyzer pass

A new mutator (similar to `RedundantAccessibilityMarker`) would:
1. Find all stored `var` properties with access broader than `private`
2. Check if any **write** references come from outside the declaring type/file
3. If no external writes exist, flag the property as a `private(set)` candidate

**New file**: e.g., `PeripherySource/periphery/Sources/SourceGraph/Mutators/PrivateSetterMarker.swift`

### 4. New annotation type

Add a new `ScanResult.Annotation` case, e.g., `.couldBePrivateSet`.

**File**: `PeripherySource/periphery/Sources/PeripheryKit/ScanResult.swift`

### 5. Treeswift UI support

Treeswift would need to display this new annotation type — icon, description, and any code-fix action (inserting `private(set)` before the `var` keyword).

### 6. Edge cases to handle

- Properties accessed via key paths (key paths can both read and write)
- Properties used in `inout` contexts
- Protocol requirements (can't be `private(set)` if the protocol requires a public setter)
- Properties with `didSet`/`willSet` observers that are triggered only internally
- Computed properties with explicit `set` blocks
- Properties in `open` classes that might be overridden
- `@objc` properties accessed from Objective-C (not visible to the Swift indexer)

## Scope Assessment

This is a **significant feature addition**, not a small tweak. It requires:

- Changes across Periphery's indexer, graph model, and analysis layers
- Careful handling of many edge cases
- A new annotation type and corresponding UI in Treeswift
- Comprehensive test coverage

## Where to Implement

This is a **general analysis change** — it improves Periphery's core detection capabilities. Per project guidelines, it should be implemented in the **upstream Periphery repository** (danwood/periphery) and pulled into Treeswift via `git subtree pull`.

## Alternatives

- **SwiftLint**: Does not have this rule either as of early 2025.
- **Manual audit**: Xcode's "Find Usages" can be used per-property, but doesn't scale.
- **Swift compiler**: No built-in warning for this. There have been Swift Evolution discussions about narrowing access levels automatically, but nothing shipped.
- **Custom script**: A lightweight approach could grep index store data for setter references, though this would be fragile and incomplete compared to a proper Periphery analysis pass.
