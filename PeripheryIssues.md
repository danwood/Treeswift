# Known Periphery Issues and Quirks

This file documents observed problems with Periphery scan results that cause false positives, incorrect positions, or other unexpected behaviors. These may be candidates for upstream fixes.

---

## 1. `@Observable` Macro: Wrong Source Positions for Synthesized Accessors

**Symptom:** `redundantInternalAccessibility` warnings for properties in `@Observable` classes report `location.line` values that point to the *macro expansion* (small line numbers like 9, 13, 28), not the actual source line where the property is declared.

**Example:**
- `var playback: PlaybackState?` is at line 55 in `AppState.swift`
- Periphery reports its location as line 28 (the closing `}` of an earlier computed property)
- The offset (27 lines) corresponds to the number of lines in supporting types defined above the class

**Root cause:** The `@Observable` macro synthesizes storage properties (`_playback`, `_inspectorContext`, etc.) and accessor boilerplate. These synthesized declarations appear in macro expansion files (`@__swiftmacro_*.swift`). The indexstore records their location as being in the originating source file, but uses the line number from the expansion file — not the actual source line.

**Impact:** When Treeswift tries to insert `private` access modifiers at those locations, it targets the wrong lines (e.g., closing braces, blank lines, doc comments), producing syntactically invalid Swift.

**Fix applied:** `ObservableMacroRetainer` now suppresses `redundantInternalAccessibility` on all implicit backing storage properties (`_propName`), so those warnings are never emitted. The `insertAccessKeyword` guard (returns line unchanged when expected keyword not found) remains as a safety net for any edge cases not covered by the retainer.

**Affected declaration kinds:** `varInstance` properties inside `@Observable` classes — specifically the synthesized storage (`_propName`) entries.

---

## 2. `assignOnlyProperty`: Property Used in `init` Body Incorrectly Removed

**Symptom:** Periphery flags a stored property as `assignOnlyProperty` and Treeswift removes the `let` declaration — but the property is assigned in the `init` body (`self.x = x`) and that assignment is left behind, causing a compile error ("value of type X has no member 'confidence'").

**Example:**
```swift
public struct DetectedPitchPoint: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let tick: TickTime
    public let pitch: Double
    public let confidence: Double   // ← Periphery flags as assignOnlyProperty, removes it
    
    public init(id: UUID = UUID(), tick: TickTime, pitch: Double, confidence: Double = 1.0) {
        self.confidence = confidence  // ← left behind → compile error
    }
}
```
File: `Units/Programs/Models/TuneTargetDisplayModels.swift`

**Root cause:** Periphery marks a stored property as `assignOnlyProperty` when it finds no *read* usages — only writes (the init assignment). However the property may genuinely need to exist as part of the struct's public interface or for future reads. Removing the declaration while leaving the init body intact breaks the build.

**Impact:** Build failure. `self.confidence = confidence` in the init becomes invalid once the property declaration is removed.

**Workaround:** Do not apply `assignOnlyProperty` removals to properties that appear in an `init` body assignment (`self.x = x`). Either skip these manually, or filter out `assignOnlyProperty` from the annotation filter when running bulk removals. The property declaration must be restored by hand if incorrectly removed.

---

## 3. Protocol Declarations Flagged as Unused When Used Only via Conformance

**Status: Fixed** — `ProtocolConformanceRetainer` now retains any protocol that has at least one conformer in the source graph.

**Symptom:** Periphery flags a `protocol` declaration as unused and Treeswift removes it, even though multiple types conform to it. The protocol body is deleted, leaving conformance declarations (`SomeType: TheProtocol`) that now fail to compile.

**Example:**
```swift
// Removed by Treeswift:
public protocol StatusRepresentable: RawRepresentable, CaseIterable, ... { ... }

// Still present — now broken:
public enum ProgramStatus: String, StatusRepresentable { ... }
public enum DealStatus: String, StatusRepresentable { ... }
```
File: `CoreData/Common/StatusProtocol.swift`

**Root cause:** Conformance references (`: TheProtocol`) are `.related` references from conforming types to the protocol. If every conforming type is itself unused, no reference chain marks the protocol as used, leaving it in `unusedDeclarations`.

**Fix:** `ProtocolConformanceRetainer` (new file in `PeripherySource/periphery/Sources/SourceGraph/Mutators/`) checks all protocol declarations and calls `graph.markRetained` on any that have at least one incoming `.related` reference whose parent is a conformable kind (class, struct, enum, or extension). Wired into the pipeline in `SourceGraphMutatorRunner.swift` after `ObservableMacroRetainer`.

---

## 4. Protocol Conformance Extensions Removed (`extension Type: Protocol`)

**Status: Fixed** — `ScanResultBuilder` now skips conformance extensions when emitting `.unused` results for extensions of unused types.

**Symptom:** Periphery flags an `extension SomeType: SomeProtocol { ... }` block as unused and Treeswift removes it. Callers that pass `SomeType` where `SomeProtocol` is expected then fail with "does not conform to expected type".

**Example:**
```swift
// Removed by Treeswift:
extension Project: Shareable { ... }

// Now fails:
func someFunc(_ item: some Shareable) { ... }
someFunc(project)   // error: 'Project' does not conform to 'Shareable'
```
File: `CoreData/Common/` (various extension files)

**Root cause:** When a concrete type is unused, `ScanResultBuilder` emits `.unused` results for all its folded extensions — including conformance extensions. Removing a conformance extension breaks any call site that passes the concrete type as the protocol type.

**Fix:** In `ScanResultBuilder.build()`, before appending an extension result, check whether `ext.related` contains a reference with `declarationKind == .protocol`. If so, skip the result — the extension is a protocol conformance block and should not be auto-removed even when the parent type is unused.

---

## 5. `unused`: Private Methods Called Only Within Same Type Incorrectly Removed

**Symptom:** Periphery flags a `private` or `private(set)` method/property as `unused` and Treeswift removes it — but the method is called by other methods within the same type. The caller compiles fine until runtime, when it crashes, or fails to compile if the method is referenced by name.

**Example:**
```swift
// Removed by Treeswift — flagged as unused:
private func purge(assetID: UUID) throws { ... }
private let logger = Logger(...)

// Still present — now broken:
func cleanupOrphans() throws {
    try purge(assetID: orphanID)     // error: cannot find 'purge' in scope
    logger.info("cleaned up")        // error: 'logger' inaccessible
}
```
Files: `Engine/EngineCacheManager.swift`, `Core/DeepLinkHandler.swift`

**Root cause (identified):** For stored `private let`/`var` properties, the Swift index store records references to the property's implicit **accessor USR** (getter/setter) rather than the property's own USR when the property is read or written. `UsedDeclarationMarker.markUsed(_:)` marks the accessor as used but does not propagate to the parent property declaration. The property never enters `usedDeclarations` and is therefore falsely flagged as unused.

**Fix applied:** `UsedDeclarationMarker.markUsed(_:)` now propagates the used status from any accessor declaration up to its parent property, mirroring the existing `functionConstructor → containing type` propagation. See `PeripherySource/periphery/Sources/SourceGraph/Mutators/UsedDeclarationMarker.swift` and `PeripherySource/periphery/README_Treeswift.md` §13 / P6.

**Scope of fix:** Addresses the stored-property case (`private let logger`). The `private func purge` case (function call) should already be handled correctly by `calledBy` relations in the index store; if a function is still falsely flagged after this fix, it may be a separate issue requiring further investigation.

**Impact:** Build failure or silent runtime breakage.

**Workaround (until fix verified):** Do not apply bulk `unused` annotation removals without manual review of each declaration. `redundantAccessibility` and `redundantInternalAccessibility` removals are much safer for bulk operation — they only adjust access modifiers, never remove code.

**Recommended safe bulk strategy:** Filter to `annotationFilter: ["redundantAccessibility", "redundantInternalAccessibility", "redundantPublicAccessibility"]` only. Review `unused` and `assignOnlyProperty` removals manually.

---

## 6. `redundantPublicAccessibility` Strips `public` From Protocol Extension Members Satisfying Public Protocol Requirements

**Symptom:** Periphery flags a `public extension SomePublicProtocol { var id: ... }` as having redundant `public`, removes it — but the `var id` inside satisfies a `public` protocol requirement (`Identifiable`). Stripping `public` from the extension makes `id` internal, breaking conformance.

**Example:**
```swift
// Before — correct:
public extension StatusRepresentable {
    var id: String { rawValue }   // satisfies Identifiable.id (public)
}

// After Treeswift strips public — broken:
extension StatusRepresentable {
    var id: String { rawValue }   // now internal → build error
}
// error: property 'id' must be declared public because it matches
// a requirement in public protocol 'Identifiable'
```
File: `CoreData/Common/StatusProtocol.swift`

**Root cause:** Periphery sees `public extension PublicProtocol` and considers `public` redundant (protocol is already public). But Swift requires the `public` on the extension to satisfy `public` protocol witness requirements — removing it demotes the members to `internal`.

**Impact:** Build failure on any type conforming to the protocol whose `id` came from the extension default.

**Workaround:** Do not apply `redundantPublicAccessibility` to protocol extensions. Skip or add `// periphery:ignore` to protocol extension declarations.

---

## 7. `unused`: Nested Types Used Only Within Parent Type Incorrectly Removed

**Symptom:** A nested `enum`/`struct` defined inside a type is removed even though it is used as a return type or parameter type by methods of the enclosing type.

**Example:**
```swift
enum DeepLinkHandler {
    enum Destination: Equatable { ... }   // ← removed as unused

    static func parse(_ url: URL) -> Destination? { ... }        // now broken
    static func toNavigationDestination(_ d: Destination) -> ... // now broken
}
```
File: `Core/DeepLinkHandler.swift`

**Root cause:** Same root cause as Issue 5 — Periphery doesn't track references to a nested type that come exclusively from within the enclosing type. The accessor-propagation fix in Issue 5 covers stored properties but not nested type declarations.

**Fix applied:** `UsedDeclarationMarker.markUsed(_:)` now also walks child function/method declarations' `returnType` and `parameterType` references when marking a parent type as used, mirroring the existing `varType` walk for child property declarations. This ensures nested types used only in sibling method signatures are marked used when the parent type is used.

**Impact:** Build failure wherever the removed type is referenced.

---

## 8. `unused`: Stored `let` Properties With No External Reads Removed, Leaving Orphan `self.x = x` in `init`

**Status: Fixed** — `AssignOnlyPropertyReferenceEliminator` now marks `let` properties with init-body setter references as retained, preventing them from appearing in `unusedDeclarations`.

**Symptom:** A `public let` property is flagged as `unused` (not `assignOnlyProperty`) and removed. The `init` body that assigns `self.x = x` is NOT removed (init stays because it's used). Build fails: "value of type X has no member 'x'".

**Example:**
```swift
public struct DetectedPitchPoint: Identifiable, Hashable, Sendable {
    public let confidence: Double    // ← flagged unused, removed

    public init(..., confidence: Double = 1.0) {
        self.confidence = confidence  // ← stays → build error
    }
}
```
File: `Units/Programs/Models/TuneTargetDisplayModels.swift`

**Root cause:** `AssignOnlyPropertyReferenceEliminator` already guards against `let` bindings (`!property.isLetBinding`). But the `unused` annotation path (separate from `assignOnlyProperty`) does not have this guard. When no external code reads `confidence`, Periphery marks the declaration `unused` and Treeswift removes only the property declaration — leaving the init assignment orphaned.

**Fix (final):** In `AssignOnlyPropertyReferenceEliminator.mutate()`, after the existing assign-only check, an `else if` branch calls `isLetPropertyWithInitBodyAssignment`. The function checks three paths: (1) a `functionAccessorSetter` child referenced from a constructor (covers unusual codegen), (2) a direct reference to the property itself or its getter from a `functionConstructor` (covers some indexer behaviors), and (3) name matching: if the property name appears as a parameter label in an explicit init of the parent type. Path 3 is the most reliable for `public let` in public structs where the Swift indexer records no references to the property at all. If any path matches, `graph.markRetained(property)` is called.

**Impact:** Build failure. The init body references a now-nonexistent property.

---

## 9. `redundantInternalAccessibility`: Stored Properties Made Private Despite Cross-File Reads

**Status: Fixed** — `isReferencedOutsideFile` now also checks implicit accessor child declarations (getter/setter USRs) for stored properties.

**Symptom:** A stored `let` or `var` property on a struct is flagged as `redundantInternalAccessibility` and marked `private`. But the property is read from other files via `instance.propertyName`, causing a build error: `'propertyName' is inaccessible due to 'private' protection level`.

**Example:**
```swift
// ProgramDisplayModel.swift — Models/Entities/
struct ProgramDisplayModel: Identifiable, Hashable, Sendable {
    let status: ProgramStatus    // ← made private by Treeswift
    let releaseDate: Date?       // ← made private by Treeswift
    ...
}

// ProductionDataView.swift — Projects/Production/  (different file)
ProgramDisplayModel(status: program.status, releaseDate: program.releaseDate, ...)
//                          ~~~~~~~~~~~~~~  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// error: 'status' is inaccessible due to 'private' protection level
```

**Root cause:** Swift's index store records reads of stored properties via their implicit **accessor child USRs** (getter USR), NOT via the property declaration's own USR. `isReferencedOutsideFile` only checked `graph.references(to: self)` — which found nothing for the property — and incorrectly concluded the property had no cross-file readers.

**Fix:** `isReferencedOutsideFile` now additionally walks `declarations` (children) when `kind == .varInstance || kind == .varStatic`, checking each child for cross-file references. This mirrors the same accessor-child pattern already used in `isReferencedFromDifferentTypeInSameFile`.

**Impact:** Build failure. Properties made `private` are inaccessible from call sites in other files.

---

## 10. `redundantPublicAccessibility`: Strips `public` From Protocol Requirement Members in Public Types

**Status: Fixed** — `markExplicitPublicDescendentDeclarations` now skips members that implement protocol requirements.

**Symptom:** Members of a `public enum`/`struct`/`class` that explicitly satisfy `public protocol` requirements have their `public` keyword removed by Treeswift. Swift then reports a conformance error because the members are no longer `public`.

**Example:**
```swift
// Before — correct:
public enum ProductionProjectInspectorType: String, CaseIterable, UnitInspectorDefinition {
    public var id: String { "production.\(rawValue)" }
    public var title: String { ... }
    public var icon: String { ... }
}

// After Treeswift strips public — broken:
public enum ProductionProjectInspectorType: String, CaseIterable, UnitInspectorDefinition {
    var id: String { ... }    // now internal → conformance error
    var title: String { ... }
    var icon: String { ... }
}
// error: property 'id' must be declared public because it matches a requirement in public protocol 'UnitInspectorDefinition'
```

**Root cause:** When `validate(_:)` marks a parent declaration as having redundant public accessibility, it calls `markExplicitPublicDescendentDeclarations(from:)` which marks ALL explicitly `public` descendants. This did not skip members that are protocol requirement witnesses — those members MUST remain `public` to satisfy the protocol contract.

**Fix:** `markExplicitPublicDescendentDeclarations` now skips any descendent declaration for which `isProtocolRequirement` returns true. The method reuses the same related-reference logic as `RedundantInternalAccessibilityMarker.isProtocolRequirement`.

**Impact:** Build failure. Protocol conformance broken — member is internal but protocol requires public.

---

## 11. `unused`: Nested Type Removed While Parent Type is Kept — Orphaned References in Parent

**Status: Fixed** — `filterSkipReferenced` now skips nested types whose parent type is not in the deletion set.

**Symptom:** A nested type (e.g. `enum Destination`) inside an outer type (e.g. `enum DeepLinkHandler`) is flagged as `unused`/`unattached` and removed. The outer type is NOT removed (it's in `shared` — referenced by other orphaned types, skipped by `skipReferenced`). Build fails because the outer type's methods return or accept the removed nested type.

**Example:**
```swift
// Core/DeepLinkHandler.swift

// DeepLinkHandler in 'shared' category — kept by skipReferenced
enum DeepLinkHandler {
    enum Destination: Equatable { ... }   // ← in 'unattached', removed

    static func parse(_ url: URL) -> Destination? { ... }        // now broken
    static func toNavigationDestination(_ d: Destination) -> ... // now broken
}

// error: cannot find type 'Destination' in scope
```

**Root cause (partially understood):** `Destination` is in `unattached`. Debug confirmed that during `filterSkipReferenced`, `hasExternalReferences(Destination)` returns `true` (refs from `parse()` and `toNavigationDestination()` methods whose parents are not in deletion set). So `Destination` IS correctly classified as "skip". But it still gets removed.

`isNestedTypeWithKeptParent` fix added three iterations (check parent not in set → check parent has external refs → check parent's children have external refs). All return the right answer in testing. Yet `Destination` still removed.

**Open question:** Is `filterSkipReferenced` even the code path that removes it? Could be a second code path (e.g. removing parent type's body via a different operation's line range, or a non-`unused` annotation path). Needs more investigation.

**Impact:** Build failure. Parent type methods reference the removed nested type.

**Partial fix committed:** `isNestedTypeWithKeptParent` added — handles the case where parent is genuinely absent from the deletion set. The specific `DeepLinkHandler.Destination` case remains broken despite the fix returning `true` for `extRefs`. Root cause not yet found.

**Workaround:** Skip `Core/DeepLinkHandler.swift` in removals until fixed.

---


