// F25 regression repro — `fileprivate` must cascade to a member `init` whose PARAMETER type was
// narrowed to fileprivate. F20 covered `func` results/params; this covers `init`, which carries no
// `func` keyword and was therefore skipped by the F20 cascade.
//
// Shape: a top-level type narrowed by Treeswift to `fileprivate` (a redundantInternalAccessibility →
// fileprivate fix) used as the element type of an implicitly-`internal` member `init`'s parameter.
// Swift then rejects the init:
//
//   error: initializer must be declared fileprivate because its parameter uses a fileprivate type
//
// Real-world origin: Prodcore baseline R-May `96e372e4` — ServiceCatalogItemEditorView.swift:
//   fileprivate struct ServiceCatalogItemData: Sendable { ... }
//   struct ServiceCatalogItemEditorView: View {
//       init(..., onSave: (ServiceCatalogItemData) -> Void, ...) { ... }   // ← needed `fileprivate`
//   }
//
// Expected after redundant-accessibility removal (`forceRemoveAll`):
//   - `struct Payload` → `fileprivate struct Payload`, AND
//   - the member `init(onCommit:)` → `fileprivate init(onCommit:)` (cascade by F25), so it compiles.
//
// Bug behavior (pre-F25): only the type became fileprivate; the `init` stayed → build failed with
// the error above.
//
// In-repo verification: end-to-end (build_errors == 0 on R-May after F25). The fix is
// `CodeModificationHelper.cascadeFileprivateToReferencingFunctions` (now matching `func`|`init`) +
// `insertFileprivateBeforeDecl`.

// swiftformat:disable all
// (Deliberate repro — keep the unannotated `init` exactly as written; it is the shape F25 must fix.)

import Foundation

// Top-level type Periphery narrows to `fileprivate` (only used file-privately below).
struct Payload: Sendable {
	let title: String
}

// A type with a member init whose parameter closure uses `Payload`. The init must itself become
// `fileprivate` once `Payload` is `fileprivate`.
struct Editor {
	private let onCommit: (Payload) -> Void

	init(onCommit: @escaping (Payload) -> Void) {
		self.onCommit = onCommit
	}
}
