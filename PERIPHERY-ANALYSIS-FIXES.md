# Periphery Analysis Fixes

**Concern A — Periphery's _analysis_ false positives and how we fixed them.** This is the single
home for every Periphery analysis bug found running Treeswift+Periphery on Prodcore: the symptom,
root cause, the fix, where it lives, its regression fixture, and its upstream-push status.

This is NOT for changes that merely make Periphery usable as a library (public APIs, progress
delegate, end-position tracking, library products) — those are **Concern B**, in
[`PeripherySource/periphery/README_Treeswift.md`](PeripherySource/periphery/README_Treeswift.md).
For the project-wide doc map see [`TREESWIFT-PROJECT-MAP.md`](TREESWIFT-PROJECT-MAP.md).

**Every entry is a bug to FIX, not to document-and-skip.** The goal is ZERO false positives: a full
`forceRemoveAll` removal of Prodcore must build with zero errors. An entry is "closed" only when the
root cause is fixed AND a regression fixture proves it stays fixed. Convergence is tracked in
[`CLEANUP-PROCESS.md`](CLEANUP-PROCESS.md) and its ledger.

## Index

Single numbering scheme: **F# = this catalog's fix number.** "P#" is the legacy
`README_Treeswift.md` subtree-change tag, kept for cross-reference; "Up" = upstream push status
(⬆️ in `danwood/periphery` master · ⏳ pending push). Detail for each F# is the correspondingly
numbered section below.

| F# | legacy P# | Title (short) | Mutator / file changed | Up | Fixture |
|---:|-----------|---------------|------------------------|----|---------|
| F1 | P1 | `@Observable` wrong source positions for synthesized accessors | `ObservableMacroRetainer` + `SourceGraphMutatorRunner` | 🔀 split (see 2026-06-12 note) | — |
| F2 | P2 | `let`-binding false positives in assignOnly detection | `DeclarationSyntaxVisitor`, `Declaration`, `SwiftIndexer`, `AssignOnlyPropertyReferenceEliminator` | ❓ re-verify (#1126) | — |
| F3 | P4 | Protocol unused when used only via conformance | `ProtocolConformanceRetainer` (new) | ❓ re-verify | ✅ moot v.up |
| F4 | P5 | Protocol conformance extensions wrongly removed | `ScanResultBuilder` (+ Treeswift `removeEmptyContainers`, `findHighestEmptyAncestor`) | ❓ re-verify | ✅ moot v.up |
| F5 | P6 | Private members called only within same type removed (stored-property case) | `UsedDeclarationMarker` (accessor → property) | ❓ re-verify | ✅ moot v.up |
| F6 | — | `redundantPublicAccessibility` strips `public` from protocol-extension members | Treeswift-side guard | — | — |
| F7 | P7 | Nested types used only in sibling method signatures removed | `UsedDeclarationMarker` (returnType/parameterType walk) | ❓ re-verify (#1075) | ✅ moot v.up |
| F8 | P9 | Stored `let` with no external reads removed, orphaning `self.x = x` | `AssignOnlyPropertyReferenceEliminator` | ❓ re-verify (#1126) | — |
| F9 | — | Stored properties made `private` despite cross-file reads | `isReferencedOutsideFile` (accessor-child walk) | ⬆️ PR #1132 | — |
| F10 | — | `redundantPublicAccessibility` strips `public` from protocol-requirement members | `markExplicitPublicDescendentDeclarations` | ⬆️ PR #1132 | — |
| F11 | P7+P8 | Nested type removed while parent kept (orphaned refs) | `UsedDeclarationMarker` (function→parent) + Treeswift `isNestedTypeWithKeptParent` | ❓ re-verify (#1075) | ✅ moot v.up |
| F12 | P10 | Ghost `redundantInternalAccessibility`, no source range, `static let` in `actor` | `DeclarationSyntaxVisitor` (secondary result at node position) | ⬆️ PR #1132 | — |
| F13 | (master d763b7a) | Nested type as **same-parent** stored-property type removed | `UsedDeclarationMarker` (nested-by-name walk) | ✅ fixed upstream (#1075) | TODO |
| F14 | P11 | Nested type **+ enum cases** removed when parent also unused | `AssignOnlyPropertyReferenceEliminator` (narrow + descendants) | ❓ re-verify (#1075) | TODO |
| F15 | P12 | Sole class `init` removed → stored props un-initializable | `AssignOnlyPropertyReferenceEliminator` (`isRequiredClassInit`) | ⚠️ overlaps declined #1058 | TODO |
| F16 | P13 | Custom type used only as a **retained Codable property's** type removed | `CodablePropertyRetainer` (`retainDeclaredType`) | ✅ fixed upstream | ✅ `RetentionTest.testRetainsCodablePropertyCustomType` |
| F17 | — | `actor` redundant-accessibility rewrite was a no-op ghost (actor classified as `.class`) | Treeswift `CodeModificationHelper.insertAccessKeyword` (class/actor keyword) + ghost-detection guard | n/a (Treeswift) | — |
| F18 | — | Files pinned via `PBXFileSystemSynchronizedBuildFileExceptionSet.membershipExceptions` deleted from disk → "Build input files cannot be found" | Treeswift `XcodeProjectFileChecker.parseSynchronizedMembershipExceptions` (also treat synchronized-group exceptions as explicit refs → shell, don't delete) | n/a (Treeswift) | ✅ E2E repro `fixtures/F18-synchronized-group-membership/` |
| F19 | — | `redundantPublicAccessibility` downgrades a type but leaves `public init`/members in its **extensions** → "cannot declare a public initializer in an extension with internal requirements" | Treeswift `CodeModificationHelper.cascadePublicStripFromExtensions` (strip `public` from extension members of any type downgraded from public) | n/a (Treeswift) | ✅ E2E repro `fixtures/F19-public-extension-member/` |
| F20 | — | Type narrowed to `fileprivate` but an **extension method / free function** returning it not cascaded → "method must be declared fileprivate because its result uses a fileprivate type" | Treeswift `CodeModificationHelper.cascadeFileprivateToReferencingFunctions` (file-wide cascade to funcs whose signature references a newly-fileprivate type) | n/a (Treeswift) | ✅ E2E repro `fixtures/F20-fileprivate-func-cascade/` |
| F21 | — | `redundantPublicAccessibility` strips `public` from a protocol-extension default-impl member that witnesses an **external** public protocol (`StatusRepresentable.id` → stdlib `Identifiable`) → "property must be declared public because it matches a requirement in public protocol" | `RedundantExplicitPublicAccessibilityMarker.validateExtension` (exempt members witnessing external-protocol requirements) | ⬆️ PR #1139 | ✅ `RedundantPublicAccessibilityTest.testPublicProtocolWitnessForExternalProtocol` |
| F22 | — | Nested enum used only as a stored-property type: the enum is retained but its **cases** are still removed, leaving an empty/invalid enum | `UsedDeclarationMarker` (mark enum cases of name-resolved types; enums only) | combine-only (recall>precision, see #1137) | ✅ `RetentionTest.testRetainsNestedTypeUsedAsSiblingStoredPropertyType` |
| F23 | — | **Top-level / sibling** type used only as another type's stored-property declared type wrongly flagged unused → dangling type annotation (generalizes F13 beyond same-parent nesting; the old PriceValue/F16 case) | `UsedDeclarationMarker` (`typesByNameInLexicalScope` / `markUsedTypesNamedByStoredProperties`) | combine-only (recall>precision, see #1137) | ✅ `RetentionTest.testRetainsSiblingTypeUsedByStoredPropertyOfUnusedType` |
| F24 | — | **NOT a FP (closed).** `DocumentCardView` etc. *looked* falsely unused, but their only use chain runs through `Archive/` — a reference-only directory that is NOT compiled. Genuine dead code; Periphery correct. | n/a (analysis correct) | n/a | ✅ `RetentionTest.testRetainsViewReferencedFromViewBuilderHelper` (guard: the `@ViewBuilder`-helper construct is correctly retained) |

> The numbered sections below still carry their original "## N." headings (N == F-number). When you
> add a fix: append the next F#, add a row here, log the subtree change in `README_Treeswift.md`,
> and add a regression fixture.

---

### Reproduction sweep (2026-06-12, late) — F3/F4/F5/F7 all MOOT on upstream f87c3f6

Each fix was re-verified against vanilla `upstream/master` with a minimal, runnable repro (the discipline learned from the #1062 "can't reproduce" rejection). None reproduced — all four are independently resolved on current upstream / Swift 6.3.2. No PRs opened.

- **F3** (protocol unused via conformance): upstream `ProtocolConformanceReferenceBuilder` + `RedundantProtocolMarker` report such a protocol as *redundant* (soft, correct), never *unused*. The Treeswift `ProtocolConformanceRetainer` predates this machinery; porting it would REGRESS upstream's redundant-protocol tests. Drop from porting list.
- **F4** (conformance extension reported unused): `ExtensionReferenceBuilder` folds same-module conformance extensions into the extended type (external-type ones are markRetained), so the extension never reaches `ScanResultBuilder` as removable. The portable `ScanResultBuilder` guard is dead code upstream. The original Treeswift symptom came from Treeswift's OWN removal helpers (`removeEmptyContainers`/`findHighestEmptyAncestor`), which are Treeswift-only and stay there.
- **F5** (private stored prop read-only flagged unused): Swift 6.3.2 index store now emits a DIRECT `var.instance` property-USR reference at each read site (not accessor-USR only), so `markUsed` retains the property with no accessor→property propagation. Catalog premise no longer holds. (F9 in PR #1132 stays valid — different path: accessibility, not used-marking.)
- **F7 / F11** (nested type used only in sibling method signatures): upstream `markUsed` already walks child methods' `returnType`/`parameterType` references. Verified by both a retention test AND a real `periphery scan` on the DeepLinkHandler shape — `Destination` retained. The Treeswift extra-walk is redundant.

Net: of the F-fix backlog, nothing remains to upstream except what's already in PR #1132 (F9/F10/F12). F1/F2/F8/F13/F14/F15/F16 were already moot/upstream. F6 excluded by design. F17–F20 are Treeswift-only.

### Upstream sync status (2026-06-12)

Verified against current upstream master (post #1075 / #1126):

- **Issue #1062 / PR #1063 is moot** — upstream #1075 fixed it; both PR-1063 tests pass on vanilla upstream. Close issue + PR.
- **PR #1042 replaced by PR #1132** (`redundant-internal-fileprivate` branch, clean 3-commit series on current upstream). Old fork `master` did not compile against current upstream (lost `unmarkRedundantInternalAccessibility` in a merge; `Declaration.name` became non-optional) — that was the cause of the all-red CI. F9/F10/F12 are folded into #1132. F6 deliberately excluded (blunt suppression; F10 covers the conformance-breaking case).
- **PR #1133** opened for the unresolvable-subproject-reference driver fix.
- **F13 and F16 are fixed upstream independently** — no port needed.
- **F1 split**: the retention half is moot (upstream now retains declared property types); the redundant-internal suppression half only makes sense on top of PR #1132 and is deferred until that lands.
- **F2/F8**: upstream #1126 retains Equatable/Hashable/Codable synthesized reads, which removes the known root causes; the blanket let-binding skip would mask real findings and should not go upstream as-is.
- **Remaining ⏳/❓ rows**: before porting anything else, re-run the Prodcore scan with current upstream Periphery and only port fixes whose false positives still reproduce.

## 1. `@Observable` Macro: Wrong Source Positions for Synthesized Accessors

**Symptom:** `redundantInternalAccessibility` warnings for properties in `@Observable` classes report `location.line` values that point to the *macro expansion* (small line numbers like 9, 13, 28), not the actual source line where the property is declared.

**Example:**
- `var playback: PlaybackState?` is at line 55 in `AppState.swift`
- Periphery reports its location as line 28 (the closing `}` of an earlier computed property)
- The offset (27 lines) corresponds to the number of lines in supporting types defined above the class

**Root cause:** The `@Observable` macro synthesizes storage properties (`_playback`, `_inspectorContext`, etc.) and accessor boilerplate. These synthesized declarations appear in macro expansion files (`@__swiftmacro_*.swift`). The indexstore records their location as being in the originating source file, but uses the line number from the expansion file — not the actual source line.

**Impact:** When Treeswift tries to insert `private` access modifiers at those locations, it targets the wrong lines (e.g., closing braces, blank lines, doc comments), producing syntactically invalid Swift.

**Fix applied:** `ObservableMacroRetainer` now suppresses `redundantInternalAccessibility` on all implicit backing storage properties (`_propName`), so those warnings are never emitted. The `insertAccessKeyword` guard (returns line unchanged when expected keyword not found) remains as a safety net for any edge cases not covered by the retainer.

**Upstream-PR investigation (2026-06-15):** The **retention** half of ObservableMacroRetainer (retain a type used only as an @Observable property's type) is NOT a reproducible bug on any Periphery-supported Swift. Bisected the full installed range — 6.1.2 (Periphery's documented minimum), 6.2.x, 6.3.x — and on EVERY version the toolchain emits the direct property-type reference, so the type is already correctly retained without the retainer. A version-gated upstream fix was built + tested (branch `fix-observable-version-aware`, green) but the gate boundary lands at/below the supported floor, so the retainer is INERT on every supported toolchain — it would only matter on hypothetical sub-6.1.2 / non-Apple toolchains. Verdict: NOT worth an upstream PR (no reproducible defect to fix); branch discarded. The retainer stays in `treeswift-extras` as a harmless safety net. The OTHER half (the wrong-line-number `redundantInternalAccessibility` suppression) depends on #1132's machinery and is a separate concern.

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


## 17. `redundantInternalAccessibility` on an `actor`: rewrite was a no-op ghost (infinite re-flag)

**Status: Fixed (Treeswift).** This is a **Treeswift removal bug**, not a Periphery analysis bug —
Periphery flagged the actor correctly.

**Symptom:** A file-local `actor` (e.g. `actor TourStatsCache`) is flagged
`redundantInternalAccessibility` (suggest `fileprivate`). Removal preview reported `deletable: 1`,
but execute wrote **nothing** to disk. On the next scan the warning re-appeared → infinite cleanup
loop that never converges.

**Example:** `Projects/Engagement/Views/Tools/MasterTour Connect/MasterTourImportConfirmationView.swift:10`
```swift
actor TourStatsCache { … }   // flagged; should become `fileprivate actor TourStatsCache`
```

**Root cause:** Periphery (via the Swift index store) classifies an `actor` as
`Declaration.Kind.class` — there is no dedicated actor kind. Treeswift's `insertAccessKeyword`
mapped `.class` → the source keyword `"class"` and searched the line for it. The line reads
`actor …`, so no match was found, and the function returned the line unchanged — a phantom "fix".

**Fix:** `insertAccessKeyword` now, for a `.class`-kind declaration, searches for `class` **or**
`actor` (word-boundary match) and inserts the access modifier before whichever is present.

**Defense-in-depth (also committed):** `computeBatchModifications` verifies an access-control
rewrite actually changed bytes; any no-op is recorded as `DeletionStats.ghostModifications` and
surfaced by the removal API as an error, so a future "fix that changes nothing" can never silently
re-flag forever. This guard caught and diagnosed Issue 17 and protects against any similar position
bug.

**Verified:** `actor TourStatsCache` → `fileprivate actor TourStatsCache` written to disk, Prodcore
builds clean, and the warning does NOT re-appear on rescan — Prodcore converges to its true floor
(0 unused, 0 redundant-accessibility, 5 `assignOnlyProperty`).

---

## F18 — Synchronized-folder `membershipExceptions` files deleted from disk

**Symptom (found by the git-history convergence experiment on baseline R-May `96e372e4`):** a
full `forceRemoveAll` deleted four fully-dead files outright —
`Shared/CoreData/Products/ProductType.swift`, `Shared/CoreData/Documents/DocumentOperations.swift`,
`Shared/CoreData/Common/IconReference.swift`, `Shared/Utilities/RegionHelpers.swift` — and the
Prodcore build then failed with:

```
error: Build input files cannot be found: '.../ProductType.swift', '.../DocumentOperations.swift',
'.../IconReference.swift', '.../RegionHelpers.swift'. (in target 'Prodcore')
```

**Root cause:** these files live in a **synchronized (blue) folder group**
(`PBXFileSystemSynchronizedRootGroup`) but are pinned individually in `project.pbxproj` via a
`PBXFileSystemSynchronizedBuildFileExceptionSet`'s `membershipExceptions` list (Xcode's modern way
to special-case target membership inside an otherwise auto-scanned folder). Xcode therefore requires
those files to exist on disk — deleting them breaks the build, exactly like a classic yellow-group
`PBXFileReference`. Treeswift's `XcodeProjectFileChecker.isSafeToDelete` only parsed the
`PBXFileReference` section, so it considered the pinned files "safe to delete" (they aren't a
`PBXFileReference`) and removed them instead of leaving an import-only shell.

**Fix (`XcodeProjectFileChecker.swift`):** added
`parseSynchronizedMembershipExceptions(from:)`, which collects every filename listed in any
`membershipExceptions = ( … )` block (entries may be bare or double-quoted relative paths). Those
filenames are unioned with the `PBXFileReference` set, so any file the project names explicitly —
yellow group **or** synchronized-group exception — is treated as not-safe-to-delete and is shelled
rather than deleted. Files discovered purely via folder scanning are still deleted when empty.

**Verified:** after the fix, a re-run `forceRemoveAll` on R-May leaves the four files as import-only
shells (they remain on disk) and Prodcore builds clean. (Treeswift-side fix; not a Periphery
analysis change.)

**Fixture:** `Prodcore-cleanup/fixtures/F18-synchronized-group-membership/` — a dead file plus the
`project.pbxproj.snippet` showing the `membershipExceptions` shape. In-repo proof is the E2E
build-clean on R-May; the unit-level assertion is `XcodeProjectFileChecker.isSafeToDelete(.../pinned
.swift) == false`.

## F19 — `public` left on extension members after the type is downgraded

**Symptom (found by the git-history convergence experiment on baseline R-May `96e372e4`):** after
the F18 fix unblocked file deletion, a full `forceRemoveAll` produced exactly four build errors, all
the same:

```
error: cannot declare a public initializer in an extension with internal requirements
  Features/Production/Inspector/ProductionInspector.swift:124
  Features/Production/Tools/ProductionToolbar.swift:118
  Shared/UI/FastPickerView.swift:368
  Shared/UI/GridPickerView.swift:395
```

Each is a generic type (e.g. `public struct ProductionToolbar<AddMenuContent: View>`) with a
constrained convenience init in a separate extension (`extension ProductionToolbar where
AddMenuContent == EmptyView { public init(...) }`).

**Root cause:** Periphery emits `redundantPublicAccessibility` for the **type** (it is only used
in-module) but not for the `public init` in the type's extension. Treeswift correctly strips
`public` from the type and its primary members, downgrading it to internal — but Swift requires a
member's declared access not exceed the effective access of its extension, which inherits the
extended type's access. With the type now internal, the extension's `public init` is illegal. The
removal of `public` from the type and the `public` on its extension members must happen together;
Periphery's per-declaration warnings don't couple them, so Treeswift must.

**Fix (`CodeModificationHelper.swift`):** `computeBatchModifications` now records the name of every
type whose `public` it removes (`publicDowngradedTypeNames`). After the existing fileprivate-cascade
pass, `cascadePublicStripFromExtensions` finds each `extension <TypeName>` block for those types and
strips a leading `public ` from the extension declaration and every member line inside it. The strip
is conservative (only an explicit leading `public `), so it cannot raise access or corrupt unrelated
lines; it simply completes the downgrade Periphery asked for.

**Verified:** after the fix a full `forceRemoveAll` on R-May builds clean (0 errors), and R-May
converges. (Treeswift-side fix; the deeper cause is a Periphery analysis gap — it could instead flag
the extension members too — which would belong upstream in `danwood/periphery`.)

**Fixture:** `Prodcore-cleanup/fixtures/F19-public-extension-member/Fixture.swift` — a `public`
generic type with a constrained-extension `public init` (carries `// swiftformat:disable all` so the
deliberate shape isn't reformatted). In-repo proof is the E2E build-clean on R-May.

## F20 — `fileprivate` type not cascaded to an extension-method / free-function result

**Symptom (found by the git-history convergence experiment on baseline R3 `23ad2547`):** after the
unused pass, a full `forceRemoveAll` produced one error:

```
Features/Production/Sequence/SequenceView.swift:724:10:
error: method must be declared fileprivate because its result uses a fileprivate type
```

`struct SectionGroup` (top-level) was narrowed by Treeswift to `fileprivate struct SectionGroup`
(a `redundantInternalAccessibility → fileprivate` fix), but `func computeSectionGroups() ->
[SectionGroup]`, declared in `extension Array where Element == SequenceEntryDisplayModel`, was left
with no access modifier. Swift requires a function whose result (or parameter) type is `fileprivate`
to be at most `fileprivate`.

**Root cause:** Treeswift's existing fileprivate cascade
(`cascadeFileprivateToAffectedDeclarations`) only patches inits/funcs inside the **type's own parent
body** and only records **nested** types (`parent != nil`). A top-level type whose users live in an
`extension <Other>` block (or a free function) is not reached.

**Fix (`CodeModificationHelper.swift`):** `computeBatchModifications` now records every type narrowed
to fileprivate/file-scope-private (top-level or nested) in `fileprivateTypeNamesForFuncCascade`.
After the existing cascades, `cascadeFileprivateToReferencingFunctions` does a file-wide pass: for
each `func` declaration line with no explicit access keyword, it collects the full (possibly
multi-line) signature and, if it references a fileprivate type, inserts `fileprivate` (preserving
leading `static`/`class`/etc. specifiers). Conservative — it never lowers a func that already
carries an explicit access keyword, so intentional public API is untouched.

**Verified:** after the fix, a full `forceRemoveAll` on R3 makes `computeSectionGroups` fileprivate
and builds clean. (Treeswift-side fix.)

**Fixture:** `Prodcore-cleanup/fixtures/F20-fileprivate-func-cascade/Fixture.swift` — a top-level
type returned by an `extension Array where …` method AND a free function (carries
`// swiftformat:disable all`). In-repo proof is the E2E build-clean on R3.

### Regression-replay finding (2026-06-14) — combine builds, but R5 scan counts jumped sharply

The `combine` branch (fresh upstream f87c3f6 + glue + #1132 + #1134 + nested-as-is) was validated in an isolated scratch Treeswift clone (`/tmp/treeswift-replay`, DerivedData `/tmp/treeswift-replay-dd`, combine source `/tmp/combine-scratch`). Real Treeswift/Prodcore untouched.

**What passed:**
- combine builds standalone (swift build, 45s) and the full test suite is green (393 tests).
- Treeswift app builds + links against combine after 5 small app-side API adaptations (patch saved: `/tmp/treeswift-app-api-adaptations.patch`). Drift was: `Reference.name` + `Declaration.name` optional→non-optional; `Scan.Output` tuple→struct (glue change); `DeclarationAttribute.name` now internal (use `.description`); `Reference.init` requires `name:`. These adaptations will be needed when the real subtree merge happens.
- App launches, automation server runs, R5 scan completes against pristine Prodcore (`a1711d27`).

**The open question (investigate later):** R5 scan counts on combine are far higher than the original experiment's R5 pass-1:
| metric | experiment R5 pass-1 | combine scan |
|---|---|---|
| unused | 271 | 638 |
| redunAcc (sum) | 464 | 773 (incl. 79 new nested-umbrella `redundantAccessibility`) |
| assignOnlyProperty | 5 | **534** |
| total | 740 | 1946 |

Config flags identical (`retainCodableProperties:true`, `retainAssignOnlyProperties:false`). Combine's Periphery mutators MATCH upstream (CodablePropertyRetainer, EquatableHashablePropertyRetainer, AssignOnlyPropertyReferenceEliminator all present, pipeline intact) — so this is fresh-upstream Periphery behaving differently from the OLD subtree the experiment ran against, NOT a combine-merge defect in the analysis code. The 79 `redundantAccessibility` are the genuinely-new nested umbrella (expected). The big unexplained jumps are **assignOnly 5→534** and **unused 271→638**.

NOT YET RUN: the decisive forceRemove→rebuild probe (would tell true-positive vs false-positive). Whether 534 assignOnly / 638 unused are real findings the old code missed, or false positives, is UNKNOWN until that probe runs. Scratch artifacts left in /tmp for that investigation.

### CORRECTION + convergence re-proof (2026-06-14, late)

**The "15/16 moot" verdict (earlier 2026-06-12 sweep) was WRONG.** Minimal upstream test fixtures did not reproduce the real Prodcore false-positive patterns at scale. The regression-replay (forceRemoveAll → rebuild Prodcore → count build errors — the experiment's actual convergence criterion) caught what fixture-testing missed.

**What combine was actually missing** (restored, each committed + pushed to origin/combine):
1. assignOnly `let`/init-body suppression — F2/F8 (PR #1136, also in combine). Dropped 534→197 reported.
2. ObservableMacroRetainer (F1) + ProtocolConformanceRetainer (F3) — whole mutators dropped. Dropped unused 638→468, redundantInternal 584→273.
3. UsedDeclarationMarker propagation walks (F5/F7/F9/F11/F13) — accessor→property (covers property-wrapper `$foo` projected values for @State), member→type, child varType/returnType/parameterType, nested-type-by-name. This was the big one: fixed the 123 `$`-binding false positives + the PhraseStatus nested-type errors.

### ROOT CAUSE of the `$foo` case + the proper upstream fix (2026-06-15)

The `$foo`-binding false positive (the 123 errors above) was root-caused by direct index-store inspection, NOT guesswork:

- It is a **real Periphery bug specific to the Xcode 27 / Swift 6.4 `@State` *macro* form.** The macro synthesizes sibling members `$foo` (a `SwiftUI.Binding`), `_foo`, `__foo`, all `implicit` and children of the view struct. A `$foo` read records a reference to the synthesized `$foo` Binding USR — never the user property's USR — so the user property gets zero incoming references and is falsely flagged unused.
- **On Xcode 26.5 (Swift 6.3.2, property-wrapper form) the bug does NOT exist** — there the `$foo` read records a direct reference to the user property, which is retained normally. The synthesized `$foo`/`_foo`/`__foo` declarations don't even appear in that index.
- Earlier "123 errors on 26.5" measurements were **toolchain-conflated**: Periphery ran under 26.5 but the Prodcore index was built by Xcode 27 (the `xcode-select` default). The clean controlled single-toolchain repro is the trustworthy evidence.

**Proper fix = PR #1138** (`fix-state-projected-value`): a new `StateProjectedValueRetainer` mutator that, when a synthesized `$foo` is referenced at a non-implicit use site, retains the sibling user property — and only then (a never-read property keeps being flagged). Structure-based, no version gate: a no-op on 26.5, fixes the macro form on 27. Verified on both toolchains; LIVE upstream, CI-green except the pre-existing-on-master `main-snapshot` lanes.

So the accessor→property walk above is **superseded by #1138** for the `$foo` case. The other walks (member→type, varType, nested-type-by-name) cover unrelated cases and stay until separately addressed (nested types → #1137). Full root-cause detail + the dual-Xcode-version index dumps are in `.claude/agent-notes/projected-value-rootcause.md`.

**Key reframe:** assignOnlyProperty + redundantProtocol are NON-REMOVABLE by design (the experiment never removes them) — their scan COUNT is cosmetic, not a convergence gate. The 141 remaining reported assignOnly are the #1058 design category (memberwise-init properties read only via synthesized code: truly assign-only but unsafe to remove) — visible-but-not-removed, correct. The real criterion is unused→0 after removal with zero build errors.

**RESULT — combine (origin/combine @ 055609f) converges ALL FOUR historical baselines:**
| baseline | commit | unused removed | stripped-build errors |
|---|---|---|---|
| R5 | a1711d27 | ~420 (4456 lines) | **0** ✅ |
| R4 | 20fb9b87 | ~4465 lines | **0** ✅ |
| R-May | 96e372e4 | ~4469 lines | **0** ✅ |
| R3 | 23ad2547 | ~16511 lines | **0** ✅ |

forceRemoveAll(unused) on each baseline → rebuild Prodcore → zero build errors = zero false positives. Combine's analysis is now proven correct against the full historical range, NOT just minimal fixtures. (F18/F19/F20 Treeswift removal-tool cascade fixes also exercised — the 17–24 insertions per baseline are their access-keyword rewrites, working.)

**Still owed:** the restored fixes (Observable, Protocol, UsedDeclarationMarker walks) are in combine but only assignOnly (#1136) + sole-class-init (#1134) have upstream PRs. The others want individual upstream PRs with real-pattern-derived tests — DEFERRED, documented here.

## F21 — `redundantPublicAccessibility` strips `public` from an external-protocol witness

**Symptom (Prodcore develop, forceRemoveAll 2026-06-16):**

```
CoreData/Common/StatusProtocol.swift: error: property 'id' must be declared public
because it matches a requirement in public protocol 'Identifiable'
```

`public protocol StatusRepresentable: …, Identifiable …` with the `id` witness supplied in a
default-implementation `public extension StatusRepresentable { var id: String { rawValue } }`. The
extension's `public` was flagged redundant; downgrading it broke the conforming public enums
(`ProgramStatus`, `ProjectStatus`, `DealStatus`), because `id` witnesses the stdlib `Identifiable`
requirement and must stay at least as accessible.

**Root cause:** `RedundantExplicitPublicAccessibilityMarker.validateExtension` marks a `public
extension` redundant whenever the extended type is itself redundant, without checking whether a
member witnesses an **external** public protocol requirement. The witness link survives as a related
reference whose USR resolves to no local declaration (the protocol — `Identifiable` — is external);
the existing cross-module exemption only handled witnesses of *local* protocols.

**Fix:** exempt an extension when any member is the witness for an external protocol requirement (a
related reference of a protocol-member-conforming kind, matching name, unresolvable USR). General —
no special-casing of `Identifiable`/`id`. **Upstream PR #1139** (`fix-public-protocol-witness`, off
upstream/master, 42 accessibility tests pass).

**Fixture:** `RedundantPublicAccessibilityTest.testPublicProtocolWitnessForExternalProtocol`.

## F22 — Nested enum retained as a property type but its cases removed

**Symptom (Prodcore develop):** a nested `enum PhraseStatus { case unknown }` used only as
`private let status: PhraseStatus` in the same struct — the enum was correctly retained, but its
case `unknown` was still flagged unused and removed, leaving an empty/invalid enum.

**Root cause:** the combine nested-type-by-name resolution (the F13 family) marked the *type* used
via `markUsed([nested])` but not its members. A type reached only by this name-based fallback has no
reference occurrences for its members, so the enum cases stayed unmarked.

**Fix (`UsedDeclarationMarker`):** when a name-resolved type is an enum, also mark its cases used. Do
this for **enums only** — marking all descendants of class/struct types over-retains and regressed
`testDoesNotRetainProtocolMethodInSubclassWithDefaultImplementation`. combine-only (the
stored-property type-resolution family is the recall-over-precision tradeoff upstream rejects per
#1137).

**Fixture:** `RetentionTest.testRetainsNestedTypeUsedAsSiblingStoredPropertyType`.

## F23 — Top-level / sibling type used only as a stored-property type removed

**Symptom (Prodcore develop):** `enum ToolPlacement { … }` (top-level) used only as
`let placement: ToolPlacement` on a sibling struct `ToolDescriptor` was flagged unused; removing it
left the surviving property's type annotation dangling ("cannot find type 'ToolPlacement' in scope").
This generalizes F13 (which covered only **same-parent** nesting) and the old PriceValue/F16 case to
any sibling or enclosing-scope type.

**Root cause:** the nested-by-name resolution only searched the owner's own `declarations` (nested
types). A top-level/sibling type referenced only as a stored property's `declaredType` was never
resolved, so it had no incoming reference.

**Fix (`UsedDeclarationMarker`):** replace the nested-only lookup with `typesByNameInLexicalScope`
(the owner's nested types, then each enclosing scope outward to the module root, inner scopes
shadowing outer) + `markUsedTypesNamedByStoredProperties`. Resolution is bounded to the lexical scope
chain — not the whole graph — to avoid retaining unrelated dead types that merely share a name.
combine-only (recall>precision, see #1137).

**Fixture:** `RetentionTest.testRetainsSiblingTypeUsedByStoredPropertyOfUnusedType`.

## Scan-cache fingerprint — hashed the wrong path (Treeswift, 2026-06-16)

Not a Periphery false positive but found this session: `SourceFingerprint.compute` walked the
configuration's `project` value (the `.xcodeproj` bundle or `Package.swift` file), which contains no
`.swift` files, so every fingerprint was the SHA-256 of an empty list — a constant that never changed.
Stale scan caches were never invalidated on relaunch (branch switch, version change). Fixed to resolve
the enclosing source directory first (matching `FileSystemScanner`/`PeripheryScanRunner`). Verified on
Prodcore develop: 862 source files, content-sensitive hash. Treeswift `SourceFingerprint.swift`.

## F24 — NOT a false positive (Periphery was correct); investigation closed (2026-06-16)

**Initial alarm (genuine-dead-code convergence run, Prodcore develop):** 47 `unused` remained that
`forceRemoveAll(unused)` would not delete (0 deletable). Triage *appeared* to show false positives —
`DocumentCardView` flagged unused yet instantiated at `ProjectContentView.swift:223`, etc.

**Resolution — Periphery is CORRECT, these are genuine dead code:**
- `DocumentCardView`'s only external use is inside `ProjectContentView`.
- `ProjectContentView`'s only external use is in `Archive/LibraryCatalog.swift`.
- `Archive/` is a **reference-only directory that is NOT compiled** — its README states "Not built,
  not imported in active code, reference only," and no `LibraryCatalog.swift.o` /
  `ProjectContentView.swift.o` exists in Prodcore's DerivedData. (It is a synchronized blue folder; the
  pbxproj membership exception is the mechanism keeping it out of the target.)
- Because Archive doesn't compile, its references produce no index data, so `ProjectContentView` is
  genuinely unused and `DocumentCardView` is genuinely unused by cascade. Periphery correctly flags
  the whole chain.

**Two corroborating proofs:** (1) the F24 investigation agent built a minimal `@ViewBuilder`-helper
reproducer and it did NOT reproduce on upstream/master under either Swift 6.3.2 or 6.4 — the graph dump
showed the reference correctly attributed, i.e. Periphery's marking logic is sound for this construct
(fixture kept as a regression guard: `RetentionTest.testRetainsViewReferencedFromViewBuilderHelper`).
(2) The compiled-object check above proves the Prodcore "use" is in uncompiled code.

**Lesson:** a source-text `grep` hit is NOT a live reference — always confirm the referencing file
actually compiles (`.o` in DerivedData / index store) before calling a Periphery `unused` finding a
false positive. The real remaining item is NOT analysis: it is why Treeswift's removal engine reports
these genuinely-dead decls as "0 deletable" (a removal-gate question, see ledger), and that some are
reachable only through an uncompiled reference folder.

## F25 — `fileprivate` type not cascaded to a member `init`'s parameter (2026-06-22)

**Symptom (found by the regression-replay run on baseline R-May `96e372e4`):** a full
`forceRemoveAll` produced one new error against a clean pristine baseline:

```
Features/Business/Views/BusinessServices/Sheets/ServiceCatalogItemEditorView.swift:72:5:
error: initializer must be declared fileprivate because its parameter uses a fileprivate type
```

Treeswift narrowed `struct ServiceCatalogItemData` to `fileprivate` (a
`redundantInternalAccessibility → fileprivate` fix). It is the element type of the view's
`init(…, onSave: (ServiceCatalogItemData) -> Void, …)` parameter. The implicitly-`internal` member
`init` was not cascaded, so Swift demanded it be at most `fileprivate`.

**Root cause:** the F20 fix (`cascadeFileprivateToReferencingFunctions`) matched **only `func`
declaration lines** (`line.contains(\bfunc\b)`). A member/initializer `init(…)` carries no `func`
keyword, so it was skipped and never cascaded. Same family as F17/F19/F20: when a type's access
changes, every declaration constrained by it must change in lockstep — this variant is the `init`
whose *parameter* uses the narrowed type.

**Fix (`CodeModificationHelper.swift`, same function):** the keyword pattern now matches
`\b(?:func|init)\b`, and `insertFileprivateBeforeFunc` → `insertFileprivateBeforeDecl` also inserts
`fileprivate` ahead of an `init` (handling failable `init?`/`init!` and the `required`/`convenience`
specifiers, plus an `init`-is-keyword-not-identifier guard so `initialData` etc. are never matched).
Conservative as before — never lowers a decl that already carries an explicit access keyword.

**Verified:** after the fix + a fresh Treeswift build, a full `forceRemoveAll` on R-May makes the
`init` fileprivate and Prodcore builds clean (0 new errors). (Treeswift-side removal-logic fix.)

**Fixture:** E2E build-clean on R-May (the regression-replay row). A minimal source shape — a
`fileprivate` struct used only as a member `init`'s parameter type — should be added under
`Prodcore-cleanup/fixtures/F25-fileprivate-init-param/` mirroring the F20 fixture.

## F26 — empty-ancestor promotion deletes a type still referenced as a type (2026-06-22)

**Symptom (found by the regression-replay run on baseline R3 `23ad2547`):** a full `forceRemoveAll`
produced 10 build errors against a clean pristine baseline, clustered on two types:

```
Shared/CoreData/Media/MediaCompositeTypes.swift: cannot find type 'VideoFormat' in scope
  (+ 'MediaFormat' does not conform to Decodable/Encodable/Equatable)
Features/Products/Import/Services/ProductImportProcessor.swift: cannot find type 'PreviewSettings'
Shared/Services/AudioAssetImporter.swift: extra arguments / missing 'from:' / contextual '.m4a'
```

**Periphery is CORRECT — this is NOT an analysis false positive.** Inspection of the R3 scan cache
(`scanResultSnapshots`) shows neither `struct VideoFormat` nor `struct PreviewSettings` is flagged
`unused`. Only their MEMBERS are flagged: every stored property → `redundantInternalAccessibility`,
and one initializer → `unused` (the others → redundant-acc). The struct itself carries no annotation.

**Root cause (Treeswift removal logic):** applying all the member-level changes (privatize every
stored property + delete the one unused init) empties the type, and
`CodeModificationHelper.findHighestEmptyAncestor` then promotes the deletion up to the WHOLE type —
without checking the type is still referenced **as a type** by a surviving declaration
(`MediaFormat.video: VideoFormat?`; `settings: PreviewSettings` parameter + a `PreviewSettings(...)`
construction). The struct is deleted while the references that name it survive → "cannot find type",
and `MediaFormat` loses its synthesized Codable/Equatable. The AudioAssetImporter errors are a pure
knock-on of the VideoFormat/MediaFormat removal. Same family as F18/F19/F20/F25 (Treeswift removal,
not Periphery) and the empty-ancestor / `shouldCheckEmptyAncestor` logic.

**Fix (`CodeModificationHelper.swift`):** new guard `isReferencedAsTypeBySurvivingDeclaration` called
inside `findHighestEmptyAncestor`. Before promoting to a parent type, it queries
`sourceGraph.references(to: parent)` for any reference with a type-usage `role`
(`varType`/`parameterType`/`returnType`/`initializerType`/… — mirrors `Reference.Role`'s
exposable set) whose owning declaration is NOT itself being deleted in this batch. If such a live
type-reference exists, the upward walk stops and the type survives. Members are still handled
individually; only the erroneous whole-type deletion is prevented. Conservative — genuinely-dead
types (no live type-reference) still collapse, so the other baselines are unaffected. (Also removed
stray leftover `DEBUG fputs` lines in the function.)

**Verified:** after the fix + a fresh Treeswift build, `forceRemoveAll` on R3 keeps both structs and
Prodcore builds clean (0 new errors); R4/R5/R-May/devbase remain clean with unchanged deletion counts.

**Fixture:** `Prodcore-cleanup/fixtures/F26-empty-ancestor-referenced-type/Fixture.swift` (a struct
whose members are all flagged, still named by a sibling type's stored property). In-repo proof is the
E2E build-clean on R3.
