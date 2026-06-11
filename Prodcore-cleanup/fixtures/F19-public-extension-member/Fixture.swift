// F19 regression repro — `public` on an extension member must be stripped when its type is
// downgraded from public.
//
// Shape: a `public` (generic) type used only in-module, with a convenience initializer declared in a
// SEPARATE constrained extension. Periphery flags the TYPE as `redundantPublicAccessibility` but
// does NOT flag the extension's `public init`. When Treeswift downgrades the type to internal, the
// extension's `public init` becomes illegal:
//
//   error: cannot declare a public initializer in an extension with internal requirements
//
// Swift requires a member's declared access not exceed its extension's effective access (which
// inherits the extended type's access). So the type downgrade and the extension-member downgrade
// must happen together.
//
// Real-world origin: Prodcore baseline R-May `96e372e4` — ProductionToolbar / ProductionInspector /
// FastPickerView / GridPickerView (generic views with a constrained-extension `public init`).
//
// Expected after redundant-accessibility removal (`forceRemoveAll`):
//   - `public struct Widget` → `struct Widget`, AND
//   - the extension's `public init()` → `init()`  (cascade by F19), so the file compiles.
//
// Bug behavior (pre-F19): only the type was downgraded; the extension `public init` stayed → build
// failed with the error above.
//
// In-repo verification: end-to-end (build_errors == 0 on R-May after F19). The fix is
// `CodeModificationHelper.cascadePublicStripFromExtensions`.

// swiftformat:disable all
// (Deliberate repro — must keep `public init` INSIDE a `where`-constrained extension, exactly the
// shape that broke. swiftformat would hoist it to `public extension { init() }`, which changes the
// shape, so formatting is disabled for this fixture file.)

import Foundation

// Used only within this module, so Periphery flags `public` as redundant.
public struct Widget<Content> {
	public let content: Content
	public init(content: Content) {
		self.content = content
	}
}

// The constrained-extension convenience init that must be downgraded in lockstep with the type.
// NOTE: `public` is on the INIT, not the extension — that is the F19 trigger.
extension Widget where Content == Int {
	public init() {
		self.init(content: 0)
	}
}

// A same-module user that keeps `Widget` referenced (so only its access — not the type — is redundant).
func makeWidget() -> Widget<Int> { Widget() }
