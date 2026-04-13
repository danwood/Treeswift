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

**Affected declaration kinds:** `varInstance` properties inside `@Observable` classes — specifically the synthesized storage (`_propName`) entries.

---

## 2. `@Observable` Macro: Types Referenced Only in Macro-Synthesized Code Marked as Unused

**Symptom:** Types used as property types inside `@Observable` classes are marked as `.unused` even though they ARE referenced — but only in the macro-generated accessor boilerplate (e.g., `ObservationTracker` code in `@__swiftmacro_*.swift` files).

**Examples from Prodcore:**
- `SidebarSection` — property type of `var requestedSidebarSection: SidebarSection?` in `AppState`
- `InspectorItem` — property type of `var inspectorItem: InspectorItem?`
- `WorkspaceScope` — property type of `var scope: WorkspaceScope` in `WorkspaceState`
- `LibrarySection` — property type of `var selectedLibrarySection: LibrarySection?` in `NavigationState`
- `DocumentTypeFilter`, `LibraryDestinationSection`

**Root cause:** Periphery's reference graph does not see references inside macro expansion files. The `@Observable` macro generates `ObservationRegistrar` calls and backing property accessors that reference these types — but since macro expansion code is not part of the reference graph, Periphery considers the types unreferenced.

**Impact:** `skipReferenced` removes these types even though removing them breaks the build — the types are still referenced in hand-written code that uses `@Observable` properties typed to them (e.g., `NavigationEnums.swift: case section(SidebarSection)`).

**Note:** This is distinct from the "only in macro expansion" case — the types appear in *both* macro-generated code AND real source. Periphery's analysis fails because it doesn't walk macro expansions for references.

**No workaround applied yet.** A possible fix: post-process scan results to remove `.unused` annotations for types that appear as property types of `@Observable` classes.

---

## 3. `skipReferenced` Does Not Guarantee Build-Safe Removals Across File Boundaries

**Symptom:** `skipReferenced` removes a type from file A, but leaves a reference to that type in file B (in the same scan scope), breaking the build.

**Example:** `SidebarSection` enum defined in `NavigationEnums.swift` is removed, but `NavigationEnums.swift` also contains `case section(SidebarSection)` which references it — these are in the same file (self-reference within the deleted enum cascade), BUT the *definition* of `SidebarSection` and the *using case* are separate declarations. Periphery may remove the definition without removing the using case.

**Root cause:** The `skipReferenced` strategy is meant to only remove items with no external references. But if two declarations reference each other circularly (type A used in type B, type B used in type A, both unused externally), Periphery may decide to remove both — but the removal order matters. If type A's definition is removed first, and type B's reference to A isn't removed in the same operation, the intermediate state is invalid.

**Broader issue:** The `skipReferenced` guarantee (removing items will not break a build) assumes Periphery's reference analysis is complete. Any gap in the reference analysis (macro expansions, conditional compilation, etc.) can cause false "safe" removals.

---

## 4. Scan Cache Positions Valid Only for Exact Source State at Scan Time

**Symptom:** After running an integration test cycle that modifies source (via removal execution) and then restores it (via `git reset`), a subsequent removal operation using the cached scan results produces wrong edits.

**Root cause:** The scan cache records declaration positions (line/column) at the time of the scan. Even if the source appears identical after `git reset` (same content), the scan positions are only guaranteed valid for the source state when the scan was run. If the scan ran against a modified version of the source (e.g., during a prior test execution before a git reset), the positions reflect that modified state.

**Rule:** Never use `--skip-scan` across test runs that modify and restore source. Always run a fresh scan with the source at the intended state before performing removal operations.

---

## 5. `build_prodcore_for_index` Does Not Update Periphery's Indexstore

**Symptom:** Running `xcodebuild clean build` against the target project before scanning does NOT update the indexstore Periphery reads.

**Root cause:** Periphery uses its own DerivedData directory (under `~/Library/Caches/com.github.peripheryapp/`) and passes `-derivedDataPath` to `xcodebuild` when it runs its own build during scanning. An external `xcodebuild` invocation writes to the standard Xcode DerivedData path, which Periphery never reads.

**Impact:** The `build_prodcore_for_index` step in the integration test script is effectively a no-op for indexstore freshness. The indexstore is only updated when Periphery itself builds the project during a scan.

**Conclusion:** To get fresh, accurate positions, the only reliable method is to trigger a fresh scan through Treeswift. Pre-scan builds via `xcodebuild` are only useful for verifying that the source compiles (not for refreshing positions).
