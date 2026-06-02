# Treeswift Modifications to Periphery

This is the **SINGLE SOURCE OF TRUTH** for all information about Treeswift's local modifications to the Periphery package. This document describes all changes, the diff minimization strategy, and the update workflow.

## Base Version

- **Upstream**: https://github.com/danwood/periphery (branch: combine-master-redundant-nested-1062)
- **Base commit**: 8ebf4a42 (includes post-3.4.0 + additional fixes)
- **Previous upstream**: https://github.com/peripheryapp/periphery (commit 5a4ac8b)
- **Current modifications**: 17 files changed, 488 insertions, 25 deletions
- **Migration**: Switched from peripheryapp/periphery to danwood/periphery combine-master-redundant-nested-1062 branch

**What's in the combine-master-redundant-nested-1062 branch:**
- All changes from upstream periphery post-3.4.0
- Redundant internal/fileprivate accessibility markers (master branch)
- Redundant nested access detection (redundant-nested branch)
- Fix to issue 1062 (fix-1062 branch)

## What Belongs Here vs. Upstream

**Only Treeswift-specific integration changes** should be applied directly to this subtree. These are changes required for Periphery to work as a library consumed by the Treeswift GUI — exposing public APIs, adding progress delegates, end-position tracking, etc.

**General Periphery analysis changes** (new scan rules, bug fixes in mutators, new detection patterns) must NOT be applied here. They belong in the upstream repository (danwood/periphery) and should be pulled into Treeswift via `git subtree pull`. If a task requires such a change, stop and make a plan to apply it to the correct upstream branch first.

**Exception — "pending upstream" fixes**: Analysis fixes that are clearly correct and general-purpose, but have not yet been contributed upstream, may be applied directly here temporarily. They MUST be documented in the [Pending Upstream Contributions](#pending-upstream-contributions) section below so they are not forgotten and can be migrated when convenient.

### Upstream Branch Workflow (CRITICAL)

The `danwood/periphery` repo has several branches that exist solely to support Treeswift. They are not intended for general Periphery users.

```
master              ← SwiftUI/AppDelegate fixes, false positive fixes, general analysis improvements
redundant-nested    ← Redundant nested access detection feature
fix-1062            ← Fix for upstream issue #1062
                         ↓ (all three merged into)
combine-master-redundant-nested-1062   ← Treeswift pulls from this branch via git subtree
```

`combine-master-redundant-nested-1062` is a **merge target** — built by merging the source branches together. **Never commit analysis changes directly to `combine-master-redundant-nested-1062`.** Doing so creates duplicate commits and breaks the merge topology.

The correct flow for any upstream analysis fix:

**Local checkout of `danwood/periphery` is at `~/code/periphery-dan-private`** (remote `origin` = `git@github.com:danwood/periphery.git`).

1. Apply the fix on the appropriate source branch:
   - General analysis fixes, SwiftUI retainer, false positive fixes → `master`
   - Redundant nested access changes → `redundant-nested`
   - Issue 1062 fix → `fix-1062`
   ```bash
   cd ~/code/periphery-dan-private
   git checkout master          # (or redundant-nested / fix-1062)
   # ... make and commit the change ...
   git push origin master
   ```
2. Rebuild `combine-master-redundant-nested-1062` by merging all source branches:
   ```bash
   git checkout combine-master-redundant-nested-1062
   git merge master
   git merge redundant-nested
   git merge fix-1062
   git push origin combine-master-redundant-nested-1062
   ```
   Resolve any conflicts — take upstream for anything not in this document's Modification Categories.
3. Pull into Treeswift via `git subtree pull` (run from the Treeswift repo root):
   ```bash
   git subtree pull --prefix=PeripherySource/periphery danwood-fork combine-master-redundant-nested-1062 --squash
   ```
4. Build to verify: `xcodebuild -project Treeswift.xcodeproj -scheme Treeswift build 2>&1 | grep -E "error:|BUILD"`

### Resolving Subtree Merge Conflicts (CRITICAL)

When `git subtree pull` produces merge conflicts, the **only correct resolution** is:

- **Take the upstream version** for any code not listed in the "Modification Categories" section below as a Treeswift-specific change
- **Preserve Treeswift additions** only for changes explicitly documented in this file

**Do NOT keep old Treeswift code just because it was there before.** If the conflict is between an old Treeswift version of something and an upstream refactor/rename, take the upstream version. The Treeswift-specific additions are a small, documented set — everything else should match upstream exactly.

After resolving conflicts, always verify by diffing against the upstream combine branch:
```bash
# Compare a specific file against upstream
git -C /Users/dwood/code/periphery-dan-private show combine-master-redundant-nested-1062:Sources/Path/To/File.swift > /tmp/upstream.swift
diff /tmp/upstream.swift PeripherySource/periphery/Sources/Path/To/File.swift
# Differences should ONLY be Treeswift additions documented below
```

Then build: `xcodebuild -project Treeswift.xcodeproj -scheme Treeswift build 2>&1 | grep -E "error:|BUILD"`

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

### 8. ObservableMacroRetainer: Fix @Observable false positives ⟶ [Pending Upstream P1]

**Purpose**: Prevent false-positive `.unused` and `redundantInternalAccessibility` warnings on types and properties inside `@Observable` classes/structs.

**Root cause**: The `@Observable` macro synthesizes backing storage and accessor boilerplate in macro-expansion files (`@__swiftmacro_*.swift`). Periphery does not walk these expansion files, so property types appear unused and properties appear file-local.

**Fix**: Wire `ObservableMacroRetainer.swift` (already present in SourceGraph/Mutators/) into the mutator pipeline.

**Change**:
- `Sources/SourceGraph/SourceGraphMutatorRunner.swift`: Added `ObservableMacroRetainer.self` after `ExternalOverrideRetainer.self`.

**Status**: Pending upstream — see [P1](#p1-observablemacroretainer-wire-into-mutator-pipeline).

---

### 9. Fix let-binding false positives in assignOnlyProperty detection ⟶ [Pending Upstream P2]

**Purpose**: Prevent false positive `assignOnlyProperty` warnings on `let` stored properties.

**Root cause**: SourceKit emits a `functionAccessorSetter` for `let` stored properties. When the property is only read via compiler-synthesized code (Codable, Hashable/Equatable, SwiftUI `@ViewBuilder`), `AssignOnlyPropertyReferenceEliminator` incorrectly flags it.

**Changes** (+14 lines across 4 files):

#### `Sources/SyntaxAnalysis/DeclarationSyntaxVisitor.swift` (+7 lines)
1. Added `isLetBinding: Bool` to `Result` tuple
2. Added `isLetBinding: Bool = false` parameter to `parse()`
3. Compute and pass `isLetBinding` in `visitPost(_ node: VariableDeclSyntax)` and `visitVariableTupleBinding()`

#### `Sources/SourceGraph/Elements/Declaration.swift` (+1 line)
1. Added `public var isLetBinding: Bool = false` property

#### `Sources/Indexer/SwiftIndexer.swift` (+1 line)
1. In `applyDeclarationMetadata`: added `decl.isLetBinding = result.isLetBinding`

#### `Sources/SourceGraph/Mutators/AssignOnlyPropertyReferenceEliminator.swift` (+5 lines)
1. Added `!property.isLetBinding` guard condition

**Status**: Pending upstream — see [P2](#p2-fix-let-binding-false-positives-in-assignonlyproperty-detection).

---

### 10. ObservableMacroRetainer: Suppress implicit backing storage warnings ⟶ [Pending Upstream P3]

**Purpose**: Prevent spurious `redundantInternalAccessibility` warnings on `@Observable` synthesized backing storage properties (`_propName`).

**Root cause**: `@Observable` synthesizes implicit `varInstance` declarations (`_propName`) whose indexstore positions point into macro expansion files, not the actual source file. Periphery assigns wrong line numbers to these declarations and may emit `redundantInternalAccessibility` warnings pointing at the wrong lines. The existing retainer loop skipped implicit properties entirely (filtered by `!$0.isImplicit`).

**Fix**: Before processing explicit properties, iterate the implicit backing storage properties of each detected `@Observable` type and call `graph.unmarkRedundantInternalAccessibility` on each.

**Change**:
- `Sources/SourceGraph/Mutators/ObservableMacroRetainer.swift`: Added loop over implicit `varInstance` declarations to unmark `redundantInternalAccessibility` before the existing explicit-property loop.

**Status**: Pending upstream — see [P3](#p3-observablemacroretainer-suppress-implicit-backing-storage-warnings).

---

### 11. ProtocolConformanceRetainer: Retain protocols with conformers ⟶ [Pending Upstream P4]

**Purpose**: Prevent false-positive `.unused` results on protocols that are conformed to but never used as existential types.

**Root cause**: Conformance references (`: TheProtocol`) are `.related` references that point FROM the conforming type TO the protocol. The `UsedDeclarationMarker` follows these through the conforming type, but only if the conforming type is itself marked used. If all conforming types are unused, the protocol has no incoming "normal" references and ends up in `unusedDeclarations`.

**Fix**: New retainer iterates all protocol declarations and retains any that have at least one incoming `.related` reference from a conformable kind (class, struct, enum, or extension).

**Changes**:
- `Sources/SourceGraph/Mutators/ProtocolConformanceRetainer.swift` (NEW FILE)
- `Sources/SourceGraph/SourceGraphMutatorRunner.swift`: Added `ProtocolConformanceRetainer.self` after `ObservableMacroRetainer.self`

**Status**: Pending upstream — see [P4](#p4-retain-protocols-that-have-at-least-one-conforming-type).

---

### 12. ScanResultBuilder: Skip conformance extensions of unused types ⟶ [Pending Upstream P5]

**Purpose**: Prevent false-positive `.unused` results on `extension Type: Protocol { ... }` blocks when the parent type is unused.

**Root cause**: `ScanResultBuilder` emits `.unused` results for all folded extensions of unused types. This includes conformance extensions. Removing a conformance extension breaks any call site that passes the concrete type where the protocol is expected, even if the concrete type has no other direct references.

**Fix**: Before appending an extension result, check whether the extension's `related` set contains a reference with `declarationKind == .protocol`. If so, skip it — the extension is a protocol conformance block and should not be auto-removed.

**Changes**:
- `Sources/PeripheryKit/ScanResultBuilder.swift`: Added `isConformanceExtension` guard in the extension-result loop

**Status**: Pending upstream — see [P5](#p5-skip-conformance-extensions-when-reporting-extensions-of-unused-types).

---

### 14. UsedDeclarationMarker: retain nested types referenced in sibling method signatures ⟶ [Pending Upstream P7]

**Purpose**: Fix false-positive `.unused` results for nested types (enums, structs) that are used only as return types or parameter types of sibling methods within the same parent type.

**Root cause**: When the Swift index store builds reference relations for a method's type annotations (return type, parameter type), the resulting references are stored on the method declaration, not the parent type. The `markUsed` walk in `UsedDeclarationMarker` already follows `varType` references from child property declarations — but it did not follow `returnType` or `parameterType` references from child function declarations. A nested type used only in sibling method signatures therefore had no path to `usedDeclarations` and was falsely flagged as unused.

**Example**: `enum Destination` nested inside `enum DeepLinkHandler` is used only as the return type of `parse(_:)` and the parameter type of `toNavigationDestination(_:)`. When those methods are not independently retained (e.g. platform-guarded callers), `Destination` falls out of `usedDeclarations`.

**Fix**: In `UsedDeclarationMarker.markUsed(_:)`, added a second walk over child declarations (after the existing `varType` walk) that iterates child function/method declarations and follows their `returnType` and `parameterType` references. Mirrors the existing pattern for `varType` on property children.

**Change**:
- `Sources/SourceGraph/Mutators/UsedDeclarationMarker.swift`: Added `for childDecl in declaration.declarations where childDecl.kind.isFunctionKind { for ref in childDecl.references where ref.role == .returnType || ref.role == .parameterType { markUsed(declarationsReferenced(by: ref)) } }` block inside `markUsed(_:)`, after the existing `varType` walk.

**Status**: Pending upstream — see [P7](#p7-useddeclarationmarker-retain-nested-types-referenced-in-sibling-method-signatures).

---

### 15. UsedDeclarationMarker: propagate used status from method/function to containing type ⟶ [Pending Upstream P8]

**Purpose**: Fix edge cases where a type is not marked used even though one of its methods is used, causing Issue 7's child-function type walk to not fire.

**Root cause**: When a static method (or any method) is called, the Swift index store sometimes records only a reference to the method USR at the call site, without a separate reference occurrence for the enclosing type. In that case the type itself is never added to `usedDeclarations` via the normal reference chain. The Issue 7 fix (section 14) walks child function returnType/parameterType refs only when the parent type is marked used — so if the parent type is not marked used, nested types referenced only in method signatures remain falsely flagged.

**Fix**: In `UsedDeclarationMarker.markUsed(_:)`, added a propagation case for all function kinds: when any method or function member is marked used, its parent declaration is also marked used. This mirrors the existing `functionConstructor → parent` and `accessor → parent property` propagation patterns.

**Change**:
- `Sources/SourceGraph/Mutators/UsedDeclarationMarker.swift`: Added `if declaration.kind.isFunctionKind, let parent = declaration.parent { markUsed([parent]) }` block inside `markUsed(_:)`, after the accessor → property propagation.

**Status**: Pending upstream — see [P8](#p8-useddeclarationmarker-propagate-used-status-from-methodfunction-to-containing-type).

---

### 13. UsedDeclarationMarker: propagate used status from accessor to parent property ⟶ [Pending Upstream P6]

**Purpose**: Fix false-positive `.unused` results for `private let`/`var` stored properties that are accessed from within the same type.

**Root cause**: When a stored property is read (e.g. `logger.info(...)`), the Swift index store records a reference to the property's implicit getter USR, not the property's own USR. The property declaration never accumulates a direct reference, so it ends up in `unusedDeclarations` even when actively used.

**Fix**: In `UsedDeclarationMarker.markUsed(_:)`, added a propagation case for accessor kinds parallel to the existing `functionConstructor → parent` case. When any accessor (getter, setter, didSet, willSet, etc.) is marked used, its parent property declaration is also marked used.

**Change**:
- `Sources/SourceGraph/Mutators/UsedDeclarationMarker.swift`: Added `if declaration.kind.isAccessorKind, let parent = declaration.parent { markUsed([parent]) }` block inside `markUsed(_:)`

**Status**: Pending upstream — see [P6](#p6-useddeclarationmarker-propagate-used-status-from-accessor-to-parent-property).

---

---

## Pending Upstream Contributions

Fixes applied here that should eventually be migrated to `danwood/periphery` `master` branch and pulled back via subtree. Each entry notes what was changed, why it's general-purpose (not Treeswift-specific), and what upstream branch it belongs on.

When contributing one of these upstream:
1. Apply the change on `master` in `~/code/periphery-dan-private`
2. Rebuild `combine-master-redundant-nested-1062` (merge master + redundant-nested + fix-1062)
3. `git subtree pull` into Treeswift
4. Remove the entry from this section (the fix now lives upstream)
5. Move the Modification Category entry to note "now upstream, preserved via subtree pull"

---

### P1. ObservableMacroRetainer: wire into mutator pipeline

**File**: `Sources/SourceGraph/SourceGraphMutatorRunner.swift`
**Change**: Added `ObservableMacroRetainer.self` after `ExternalOverrideRetainer.self`
**Why general-purpose**: Any codebase using `@Observable` will get false `.unused` and `redundantInternalAccessibility` warnings. Not Treeswift-specific.
**Upstream branch**: `master`
**Also involves**: `ObservableMacroRetainer.swift` itself (the file) — already exists in the subtree; if upstream doesn't have it, it must be added there too.

---

### P2. Fix let-binding false positives in assignOnlyProperty detection

**Files**: `DeclarationSyntaxVisitor.swift`, `Declaration.swift`, `SwiftIndexer.swift`, `AssignOnlyPropertyReferenceEliminator.swift`
**Change**: Track `isLetBinding` flag through indexing pipeline; skip assign-only elimination for `let` properties.
**Why general-purpose**: `let` stored properties should never be flagged as assign-only. Affects any codebase with Codable/Hashable/Equatable synthesis.
**Upstream branch**: `master`

---

### P3. ObservableMacroRetainer: Suppress implicit backing storage warnings

**File**: `Sources/SourceGraph/Mutators/ObservableMacroRetainer.swift`
**Change**: Added loop over implicit `varInstance` declarations (`_propName`) in detected `@Observable` types to call `graph.unmarkRedundantInternalAccessibility` before the existing explicit-property loop.
**Why general-purpose**: Any codebase using `@Observable` can receive spurious `redundantInternalAccessibility` warnings on synthesized backing storage properties whose source positions point into macro expansion files. Not Treeswift-specific.
**Upstream branch**: `master`

---

### P4. Retain protocols that have at least one conforming type

**Files**:
- `Sources/SourceGraph/Mutators/ProtocolConformanceRetainer.swift` (NEW FILE)
- `Sources/SourceGraph/SourceGraphMutatorRunner.swift` (add retainer to pipeline)

**Change**: New `ProtocolConformanceRetainer` mutator scans all protocol declarations and calls `graph.markRetained` on any protocol that has at least one `.related` reference whose parent is a conformable kind (class, struct, enum, or extension). This prevents protocols used only via conformance from being flagged as `.unused` and removed.

**Why general-purpose**: Any codebase with internal protocols that are only conformed to (never used as existential types) will get false-positive `.unused` results that cause destructive removals — the protocol body is deleted while conformance declarations remain, breaking compilation.
**Upstream branch**: `master`

---

### P5. Skip conformance extensions when reporting extensions of unused types

**File**: `Sources/PeripheryKit/ScanResultBuilder.swift`

**Change**: In the loop that emits `.unused` results for extensions of unused types, added a guard that skips any extension whose `related` set contains a reference with `declarationKind == .protocol`. Such extensions are `extension Type: Protocol { ... }` conformance blocks. Removing them silently breaks call sites that pass the conforming type where the protocol is expected.

**Why general-purpose**: Any codebase using protocol conformance extensions is at risk of having them incorrectly flagged as unused when the concrete type has no direct references but is used implicitly through its protocol conformance.
**Upstream branch**: `master`

---

### P6. UsedDeclarationMarker: propagate used status from accessor to parent property

**File**: `Sources/SourceGraph/Mutators/UsedDeclarationMarker.swift`

**Change**: In `markUsed(_:)`, when a declaration of an accessor kind (getter/setter/didSet/willSet/etc.) is marked used, also mark its parent property declaration as used. Mirrors the existing constructor → containing-type propagation pattern.

**Why needed**: The Swift index store records references to implicit accessor USRs (e.g. the getter of `private let logger`) rather than the property's own USR when the property is read or written. Without this propagation, the property declaration itself is never added to `usedDeclarations`, so it appears in `unusedDeclarations` and is flagged as unused — even though the property is actively used via its accessor.

**Why general-purpose**: Any codebase with `private let` or `private var` properties read within the same type can trigger this false positive. Not Treeswift-specific.

**Upstream branch**: `master`

---

### P7. UsedDeclarationMarker: retain nested types referenced in sibling method signatures

**File**: `Sources/SourceGraph/Mutators/UsedDeclarationMarker.swift`

**Change**: In `markUsed(_:)`, added a walk over child function/method declarations — after the existing `varType` walk for properties — that follows their `returnType` and `parameterType` references. When the parent type is marked used, any nested type referenced only in a sibling method's return or parameter type annotation is also marked used.

**Why needed**: A nested enum or struct used only as a return/parameter type has no external references of its own. Without this walk, it falls out of `usedDeclarations` and is falsely flagged as `.unused`. The existing `varType` walk for child property declarations addresses the same problem for properties; this extends the pattern to functions.

**Why general-purpose**: Any codebase with a nested type used only within its parent's method signatures can trigger this false positive. Not Treeswift-specific.

**Upstream branch**: `master`

---

### P8. UsedDeclarationMarker: propagate used status from method/function to containing type

**File**: `Sources/SourceGraph/Mutators/UsedDeclarationMarker.swift`

**Change**: In `markUsed(_:)`, when any function-kind declaration (instance method, static method, class method, free function, constructor, etc.) is marked used, also mark its parent declaration as used. Mirrors the existing constructor → containing-type and accessor → property propagation patterns.

**Why needed**: The Swift index store sometimes records only a reference to the method USR at a call site, without emitting a separate type-reference occurrence for the enclosing type. When that happens, the type is not added to `usedDeclarations` through the normal reference chain. Because the Issue 7 (P7) child-function walk fires only when the parent type is already marked used, a type reachable only through its static-method call sites could silently bypass the walk, leaving nested types falsely unused.

**Why general-purpose**: Any codebase with an enum or struct that is accessed exclusively through static-method call sites (no explicit type-annotation usage) could encounter this if the index store omits the enclosing-type reference. Not Treeswift-specific.

**Upstream branch**: `master`

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
- ⚠️ `Sources/SourceGraph/SourceGraphMutatorRunner.swift` - ObservableMacroRetainer pipeline entry
- ⚠️ `Sources/SourceGraph/Mutators/ObservableMacroRetainer.swift` - Implicit backing storage suppression (section 10)

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

**IMPORTANT — Keep subtree up to date**: When analysis fixes or improvements are committed to `danwood/periphery` master (e.g., false positive fixes, new detection rules), the subtree here must be updated to pick them up. The fix workflow is:

1. Commit fix to correct source branch in `danwood/periphery` (usually `master`)
2. Merge that branch into `combine-master-redundant-nested-1062` in `danwood/periphery`
3. Pull subtree into Treeswift (see command below)
4. Resolve any merge conflicts, preserving Treeswift-specific modifications (see sections above)
5. Build and verify: `xcodebuild -project Treeswift.xcodeproj -scheme Treeswift build`

**Current Setup:**
```bash
# Configured remotes
git remote add periphery-upstream https://github.com/peripheryapp/periphery.git  # Original upstream
git remote add danwood-fork https://github.com/danwood/periphery                 # Current source
```

**To update to the latest combine-master-redundant-nested-1062 branch:**

```bash
# Pull the latest combine-master-redundant-nested-1062 branch from danwood fork
git fetch danwood-fork combine-master-redundant-nested-1062
git subtree pull --prefix=PeripherySource/periphery danwood-fork combine-master-redundant-nested-1062 --squash

# Resolve any conflicts, preserving Treeswift-specific modifications documented above
# Then build to verify:
xcodebuild -project Treeswift.xcodeproj -scheme Treeswift build 2>&1 | grep -E "error:|BUILD"
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
combine-master-redundant-nested-1062
```bash
# View all local modifications against danwood fork baseline
git diff danwood-fork/combine-master-redundant-nested-1062 HEAD -- PeripherySource/periphery/

# Generate patch file
git diff danwood-fork/combine-master-redundant-nested-1062 HEAD -- PeripherySource/periphery/ > current_modifications.patch

# View statistics
git diff --stat danwood-fork/combine-master-redundant-nested-1062 HEAD -- PeripherySource/periphery/
```

**Note**: The current baseline is commit `8ebf4a42` from danwood/periphery combine-master-redundant-nested-1062 branch. All diffs against this show only Treeswift modifications, not danwood fork changes.

## References

- Upstream Periphery: https://github.com/peripheryapp/periphery
- Main project documentation: [CLAUDE.md](../../CLAUDE.md)
- Implementation notes: [IMPLEMENTATION_NOTES.md](../../IMPLEMENTATION_NOTES.md)
- Patch application summary: [PATCH_APPLICATION_SUMMARY.md](../PATCH_APPLICATION_SUMMARY.md)

---

*Periphery base: 3.4.0+ (commit 5a4ac8b)*
*Baseline commit: 4dd2a038*
*Last updated: 2026-06-01*