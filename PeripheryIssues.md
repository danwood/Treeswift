# Known Periphery Issues and Quirks

This file catalogs false positives and analysis bugs found while running Treeswift+Periphery on
Prodcore. **Every entry here is a bug to FIX, not to document-and-skip.** The project goal is
ZERO false positives: a full `forceRemoveAll` removal of Prodcore must build with zero errors.

An entry is only "closed" when (a) the root cause is fixed in Periphery or Treeswift, and (b) a
regression fixture in `Prodcore-cleanup/fixtures/` proves it stays fixed. Convergence is tracked
in `Prodcore-cleanup/convergence-ledger.md` and audited by the `cleanup-supervisor` agent. A
"Workaround:" line is a temporary stopgap only — it must be replaced by a "Fix applied:" line.

See `.claude/prodcore.md` for the measured loop and `.claude/agents/cleanup-supervisor.md` for
the supervisor that prints the progress table.

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

**Status: Fixed** — Three separate bugs all contributed to conformance extensions being wrongly removed. All three fixed.

**Symptom:** Periphery flags an `extension SomeType: SomeProtocol { ... }` block as unused and Treeswift removes it. Callers that pass `SomeType` where `SomeProtocol` is expected then fail with "does not conform to expected type".

**Example:**
```swift
// Removed by Treeswift:
extension Project: Shareable { ... }

// Now fails:
func someFunc(_ item: some Shareable) { ... }
someFunc(project)   // error: 'Project' does not conform to 'Shareable'
```
File: `CoreData/Projects/Project+Extensions.swift`

**Root causes (three independent bugs):**

1. **ScanResultBuilder — extensions of unused parent types:** When a concrete type is unused, `ScanResultBuilder` emits `.unused` results for all its folded extensions, including conformance extensions. Fix: added `isConformanceExtension` guard in the extension-result loop (already applied).

2. **ScanResultBuilder — standalone empty conformance extensions:** When an `extension Type: Protocol {}` has no body members, Periphery directly adds it to `unusedDeclarations`. `ScanResultBuilder` then emits it as a top-level `.unused` result. The Issue 4 guard only checked folded extensions (path 1) — it did not guard against the declaration itself being emitted as unused. Fix: added second guard at the `return [ScanResult(...)] + extensionResults` line: if `removableDeclaration.kind == .extension` and its `related` set contains a `.protocol` ref, return `[ScanResult]()`.

3. **DeclarationDeletionHelper.removeEmptyContainers — comment-only body:** After declarations are removed from other extensions in the same file, `removeEmptyContainers` post-processes the modified source to clean up empty `extension`/`class`/`struct` blocks. An `extension Type: Protocol { // comments }` body with only comment lines passes the `bodyIsEmpty` check (comments are explicitly allowed) → the extension gets removed silently. Fix: added `isConformanceExtension` guard in `removeEmptyContainers` — any extension line containing `: SomeName` before `{` is skipped.

**Additional related fix:** `findHighestEmptyAncestor` in `CodeModificationHelper` had a vacuous-truth bug — `parent.declarations.allSatisfy { ... }` returns `true` on an empty declarations set, which could spuriously promote deletions to empty container parents. Added `guard !parent.declarations.isEmpty else { break }`.

**Impact:** Build failure. Protocol conformance broken — type no longer satisfies protocol at call sites.

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

**Fix applied (stored-property case):** `UsedDeclarationMarker.markUsed(_:)` now propagates the used status from any accessor declaration up to its parent property, mirroring the existing `functionConstructor → containing type` propagation. See `PeripherySource/periphery/Sources/SourceGraph/Mutators/UsedDeclarationMarker.swift` and `PeripherySource/periphery/README_Treeswift.md` §13 / P6. The `private let logger` false positive is resolved.

**Current state of `EngineCacheManager` (as of 2026-06-05):** The `private func purge` case was based on an earlier version of the file. The current `EngineCacheManager.swift` does not have a `private func purge` — `purge` is internal and correctly flagged as unused (it has no callers outside the file, and `cleanupOrphanFiles`/`cleanupStaleFiles` which call it are themselves unused). This is a genuine "all methods unused" scenario, not a false positive. The remaining concern is cascade ordering: 11 methods are flagged unused, but `cacheURL(for:signature:)` and `sanitizeFilename(_:)` are NOT flagged (they are called by the flagged methods). If the 11 methods are removed, `cacheURL` and `sanitizeFilename` become dead code not captured in this scan pass.

**Residual issue:** Treeswift/Periphery currently cannot perform multi-pass cascade removal of a deeply interconnected call chain where intermediate nodes have external callers. This is a known limitation, not a bug. The safe approach is to remove the entire type in one operation (if the type itself is unused) or to manually review removals in files with internal call chains.

**Impact:** Build failure or silent runtime breakage.

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

**Status: Fixed** — The P7/P8 fixes to `UsedDeclarationMarker` (sections 14 and 15 in `README_Treeswift.md`) resolved the root cause. `Destination` is no longer flagged as unused at all: when `parse()` and `toNavigationDestination()` are marked used, the parent `DeepLinkHandler` is also marked used (P8), and then its child methods' `returnType`/`parameterType` references are walked (P7), marking `Destination` as used.

**Symptom:** A nested type (e.g. `enum Destination`) inside an outer type (e.g. `enum DeepLinkHandler`) is flagged as `unused`/`unattached` and removed. The outer type is NOT removed (it's in `shared` — referenced by other orphaned types, skipped by `skipReferenced`). Build fails because the outer type's methods return or accept the removed nested type.

**Example:**
```swift
// Core/DeepLinkHandler.swift

// DeepLinkHandler in 'shared' category — kept by skipReferenced
enum DeepLinkHandler {
    enum Destination: Equatable { ... }   // ← was in 'unattached', removed

    static func parse(_ url: URL) -> Destination? { ... }        // now broken
    static func toNavigationDestination(_ d: Destination) -> ... // now broken
}

// error: cannot find type 'Destination' in scope
```

**Root cause:** Two issues interacted. First, `DeepLinkHandler` was not being added to `usedDeclarations` even when its static methods were called (P8 fix). Second, nested type `Destination` used only in sibling method signatures (return/parameter types) was not walked when the parent was marked used (P7 fix).

**Fixes applied:** P7 (`UsedDeclarationMarker` walks child function returnType/parameterType refs) and P8 (`UsedDeclarationMarker` propagates function-used → parent-used). With both fixes, `Destination` is no longer emitted as a scan result and is never removed.

**Additional fix committed (Treeswift):** `isNestedTypeWithKeptParent` in `UnusedDependencyAnalyzer` provides a safety net: a nested type whose parent is not in the deletion set is always skipped during removal. This defense-in-depth catch is preserved even though the Periphery fixes mean `Destination` shouldn't appear in results at all.

**Note on earlier investigation:** Debug had confirmed `filterSkipReferenced` returned `extRefs=true` for `Destination` yet removal still happened — suggesting a second removal code path. With the P7/P8 upstream fixes, `Destination` never enters the deletion set, bypassing that code path entirely.

---

## 12. `redundantInternalAccessibility`: Ghost Warning With No Source Range for `static let` Inside `actor`

**Status: Fixed** — `DeclarationSyntaxVisitor.visitPost(_ node: VariableDeclSyntax)` now registers a secondary result entry at the `VariableDeclSyntax` node start position (the `static`/`let`/`var` keyword) when it differs from the binding position. This allows `visitDeclarations` to match the index-store-recorded position and populate end-position data.

**Symptom:** Periphery flags a `static let` property inside an `actor` type as `redundantInternalAccessibility`. Treeswift shows 1 deletable in preview but applying it writes nothing to disk. On next scan the warning reappears — infinite loop.

**Example:**
```swift
// Projects/Engagement/Views/Tools/MasterTour Connect/MasterTourImportConfirmationView.swift
actor TourStatsCache {
    static let shared = TourStatsCache()  // ← redundantInternalAccessibility, no range
}
```

**Root cause:** Position mismatch between Swift index store and `DeclarationSyntaxVisitor`. Index store records `static let shared` at the `static` keyword position. Syntax visitor uses `binding.positionAfterSkippingLeadingTrivia` (the `shared` identifier position). Positions don't match → `matchingResult` nil in `SwiftIndexer.applyDeclarationMetadata` → no `endLine`/`endColumn` → no source range.

**Fix applied (Periphery subtree):** In `visitPost(_ node: VariableDeclSyntax)`, after parsing the binding at `binding.positionAfterSkippingLeadingTrivia`, check if `node.positionAfterSkippingLeadingTrivia` differs (i.e., there are leading modifiers like `static`). If so, call `parse(...)` a second time with `at: node.positionAfterSkippingLeadingTrivia` and the same `endPosition`. This registers a second `Location → Result` entry in `resultsByLocation`, ensuring the index-store-recorded position gets a match.

**Additional mitigation (Treeswift):** `canRemoveCode` requires `hasFullRange` for accessibility annotations. Retained as a safety net for any future no-range items.

**Impact (before fix):** Persistent ghost warning — shown as 1 non-deletable after Treeswift mitigation, or as 1 phantom deletable that never writes to disk.

**See:** `README_Treeswift.md` §17 / P10 for upstream contribution details.

---

## 13. `unused`: Nested Type Used as a Same-Parent Stored-Property Type Removed

**Status: Fixed** — `UsedDeclarationMarker` Issue-13 walk (README_Treeswift.md §13, upstream master d763b7a).

**Symptom:** A nested type used only as the declared type of a stored property within the same
parent type is flagged unused and removed, leaving the property's type annotation unresolvable.

**Example:**
```swift
struct PhraseRange {
    private let status: PhraseStatus      // type annotation
    enum PhraseStatus { case unknown }    // ← removed; `status` now references a missing type
}
```
File: `Units/Programs/Models/TuneTargetDisplayModels.swift`

**Root cause:** The Swift index store does not always emit a reference occurrence when a nested
type is used as the type annotation of a same-scope stored property. No reference → falsely unused.

**Fix:** `UsedDeclarationMarker.markUsed(_:)` collects a parent's nested concrete types by name and
marks any whose name matches a sibling property's `declaredType` (sanitized) as used.

---

## 14. `unused`: Nested Type AND Its Enum Cases Removed When Both Parent and Type Are Unused

**Status: Fixed** — `AssignOnlyPropertyReferenceEliminator` marks the nested type and all its
descendants (enum cases, members) used when it is a sibling property's declared type, even when
the parent type is itself unused.

**Symptom:** Same shape as Issue 13, but the Issue-13 walk only fires when the **parent** type is
marked used. When the parent (`PhraseRange`) is itself unused, the nested `PhraseStatus` enum was
still flagged. Worse: the enum *case* (`case unknown`) was flagged `unused` independently — after
Treeswift removed the case, empty-container cleanup swept away the now-empty `enum PhraseStatus`,
re-orphaning `private let status: PhraseStatus`.

**Example:** `enum PhraseStatus { case unknown }` inside an unused `struct PhraseRange`, used as
`private let status: PhraseStatus`. File: `Units/Programs/Models/TuneTargetDisplayModels.swift`.

**Root cause:** Two gaps. (1) Issue-13's protection is conditional on the parent being used.
(2) Marking only the nested *type* used leaves its enum *cases* flagged, and empty-container
post-processing then removes the whole enum.

**Fix:** In `AssignOnlyPropertyReferenceEliminator.mutate()`, for every concrete type whose name
matches a sibling property's `declaredType` (same-parent), call `graph.markUsed` on the type AND
on every `descendentDeclarations` entry (cases, members). `markUsed` (not `markRetained`) is
required: nested decls are "retained" via a retained reference rather than via
`retainedDeclarations`, and `ScanResultBuilder`'s final filter only checks `retainedDeclarations`.

**Still open (generalization):** A **top-level** type used as a property type *in a different
type* (e.g. `fileprivate struct PriceValue` used as `let price: PriceValue` inside another
struct) is NOT covered — its parent is the module, not the property's enclosing type. See ledger
"Open False Positives". Needs a graph-wide "type referenced as any surviving property's type"
retainer or a Treeswift removal-time guard.

---

## 15. `unused`: Sole Class Initializer Removed, Leaving Stored Properties Un-initializable

**Status: Fixed** — `AssignOnlyPropertyReferenceEliminator.isRequiredClassInit` retains it.

**Symptom:** The only explicit `init` of a `class` (which, unlike a struct, gets no synthesized
memberwise init) is flagged `unused` and removed. Stored properties with no default value become
un-initializable → build error.

**Example:**
```swift
fileprivate class WebPage: NSObject {
    private var urlRequest: URLRequest        // no default value
    init(url: URL) { self.urlRequest = URLRequest(url: url); super.init() }  // ← removed
}
```
File: `Components/WebView.swift`. (Post-fix: the init is downgraded to `private` rather than
removed — safe, since it is only used in-type.)

**Root cause:** The init has no external callers, so Periphery flags it unused. But for a class
with non-default stored properties it is structurally required.

**Fix:** `isRequiredClassInit(_:)` retains a `functionConstructor` that is the sole non-implicit
init of a `class` parent and assigns at least one stored property (detected via setter / direct
references from a `functionConstructor`).

---

## 16. `unused`: Custom Type Used Only as a Retained `Codable` Property's Type Removed

**Status: Fixed** — `CodablePropertyRetainer` now retains the declared type (+ descendants) of each
retained Codable/Encodable property.

**Symptom:** A custom type used only as the declared type of a `Codable`/`Encodable` property is
flagged `unused` and removed, while the property itself is retained (by `CodablePropertyRetainer`),
leaving the property's type annotation unresolvable → build error.

**Example:**
```swift
fileprivate struct PriceLookupResponse: Decodable {
    struct ProductInfo: Decodable {
        let price: PriceValue          // ← property retained (Codable)
    }
}
fileprivate struct PriceValue: Decodable {  // ← removed; `price` now references a missing type
    let decimal: Decimal
    init(from decoder: Decoder) throws { ... }
}
```
File: `Main/Gear/PriceLookup/ClaudePriceLookupService.swift`

**Root cause:** `CodablePropertyRetainer` retains a Codable type's stored properties (so synthesized
coding keeps working) but did NOT retain the *types* those properties are declared as. When such a
type is a separate custom type with no other references, it falls into `unusedDeclarations` and is
removed even though a retained property depends on it.

**Fix:** `CodablePropertyRetainer.retainDeclaredType(of:)` resolves each retained property's
sanitized `declaredType` to concrete type declarations (indexed graph-wide by simple name) and
`markRetained`s them plus their descendants. Restricting to the declared types of *retained*
properties keeps genuinely-dead type+property pairs removable (preserving convergence).

**Note on a rejected broader fix:** An earlier attempt generalized Issue 14 into a graph-wide "mark
used any type used as any property's declaredType" sweep. The mass `markUsed` perturbed
`ignoreUnusedDescendents`, surfacing many previously-ignored declarations as removable and causing
a ~90-error, 29-file over-removal regression (recorded in the convergence ledger). The targeted
retained-property-only approach above avoids this.

---

