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

**Workaround applied in Treeswift:** `insertAccessKeyword` now returns the line unchanged when the expected declaration keyword (e.g., `var`, `let`) is not found on that line. This prevents corruption but means the access-control fix is silently skipped for these properties.

**Partial fix applied:** `ObservableMacroRetainer` now suppresses `redundantInternalAccessibility` on implicit backing storage properties (`_propName`), so those warnings are no longer emitted. The `insertAccessKeyword` guard remains as a safety net for any remaining edge cases.

**Affected declaration kinds:** `varInstance` properties inside `@Observable` classes — specifically the synthesized storage (`_propName`) entries.

---

## 2. `skipReferenced` Does Not Guarantee Build-Safe Removals Across File Boundaries

**Symptom:** `skipReferenced` removes a type from file A, but leaves a reference to that type in file B (in the same scan scope), breaking the build.

**Example:** `SidebarSection` enum defined in `NavigationEnums.swift` is removed, but `NavigationEnums.swift` also contains `case section(SidebarSection)` which references it — these are in the same file (self-reference within the deleted enum cascade), BUT the *definition* of `SidebarSection` and the *using case* are separate declarations. Periphery may remove the definition without removing the using case.

**Root cause:** The `skipReferenced` strategy is meant to only remove items with no external references. But if two declarations reference each other circularly (type A used in type B, type B used in type A, both unused externally), Periphery may decide to remove both — but the removal order matters. If type A's definition is removed first, and type B's reference to A isn't removed in the same operation, the intermediate state is invalid.

**Broader issue:** The `skipReferenced` guarantee (removing items will not break a build) assumes Periphery's reference analysis is complete. Any gap in the reference analysis (macro expansions, conditional compilation, etc.) can cause false "safe" removals.

