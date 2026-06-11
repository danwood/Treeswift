// F20 regression repro — `fileprivate` must cascade to an extension-method / free-function whose
// result (or parameter) type was narrowed to fileprivate.
//
// Shape: a top-level type narrowed by Treeswift to `fileprivate` (a redundantInternalAccessibility →
// fileprivate fix), returned by a `func` declared in an `extension <Other>` block (NOT a sibling in
// the type's own scope). The existing same-scope cascade does not reach extension/free functions, so
// the func is left without an access modifier and Swift rejects it:
//
//   error: method must be declared fileprivate because its result uses a fileprivate type
//
// Real-world origin: Prodcore baseline R3 `23ad2547` — SequenceView.swift:
//   fileprivate struct SectionGroup { ... }
//   extension Array where Element == SequenceEntryDisplayModel {
//       func computeSectionGroups() -> [SectionGroup] { ... }   // ← needed `fileprivate`
//   }
//
// Expected after redundant-accessibility removal (`forceRemoveAll`):
//   - `struct Section` → `fileprivate struct Section`, AND
//   - the extension method `func groups() -> [Section]` → `fileprivate func groups() -> [Section]`
//     (cascade by F20), so the file compiles.
//
// Bug behavior (pre-F20): only the type became fileprivate; the extension method stayed → build
// failed with the error above.
//
// In-repo verification: end-to-end (build_errors == 0 on R3 after F20). The fix is
// `CodeModificationHelper.cascadeFileprivateToReferencingFunctions`.

// swiftformat:disable all
// (Deliberate repro — keep the explicit `extension Array where Element == String` and the
// unannotated funcs exactly as written; they are the shape the F20 cascade must fix.)

import Foundation

// Top-level type Periphery narrows to `fileprivate` (only used file-privately below).
struct Section: Identifiable, Hashable {
	let id: String
	let title: String
}

// An extension method on a DIFFERENT type whose result uses `Section`. Must itself become
// `fileprivate` once `Section` is `fileprivate`.
extension Array where Element == String {
	func groups() -> [Section] {
		enumerated().map { Section(id: "\($0.offset)", title: $0.element) }
	}
}

// A free function in the same file, also constrained by `Section` — must cascade too.
func firstGroup(of items: [String]) -> Section? {
	items.groups().first
}
