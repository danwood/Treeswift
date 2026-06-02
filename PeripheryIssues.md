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

**Root cause:** Periphery considers a protocol "unused" if no code calls its methods or reads its associated types directly. Conformance declarations (`: TheProtocol`) are not counted as usage of the protocol itself.

**Impact:** Build failure. All types conforming to the removed protocol fail to compile.

**Workaround:** Skip `CoreData/Common/StatusProtocol.swift` and similar pure-protocol files from bulk removal. Add `// periphery:ignore` to protocol declarations that are used only via conformance, or exclude such files from the nodeIds list.

---

## 4. Protocol Conformance Extensions Removed (`extension Type: Protocol`)

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

**Root cause:** Periphery sees the conformance extension body as unreferenced if no code explicitly calls the protocol's methods through that conformance. Protocol-typed parameters that accept the conforming type are not tracked as "using" the conformance.

**Impact:** Build failure anywhere the conforming type is passed as the protocol type.

**Workaround:** Do not apply bulk removal to extension files that declare protocol conformances. Inspect these manually and skip. Add `// periphery:ignore` to conformance extensions if they must remain.

---


