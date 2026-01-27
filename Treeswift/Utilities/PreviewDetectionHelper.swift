//
//  PreviewDetectionHelper.swift
//  Treeswift
//
//  Helper for detecting #Preview macros that reference SwiftUI Views being deleted
//

import Foundation
import SourceGraph

/**
 Detects #Preview macro declarations that reference SwiftUI Views.

 Uses Periphery's SourceGraph to identify implicit declarations created by #Preview macros
 and determine which Views they reference. This enables automatic cleanup of orphaned
 preview code when deleting unused Views.
 */
struct PreviewDetectionHelper {
	/// USR (Unified Symbol Resolution) for the PreviewRegistry protocol from DeveloperToolsSupport framework.
	/// All #Preview macro expansions create implicit code that references this protocol.
	private static let previewRegistryUsr = "s:21DeveloperToolsSupport15PreviewRegistryP"

	/**
	 Finds all #Preview macro declarations that reference the given View.

	 The #Preview macro creates implicit declarations marked with `isImplicit = true`.
	 These implicit declarations reference the PreviewRegistry protocol and contain
	 references to the Views they preview.

	 - Parameters:
	   - viewDeclaration: The SwiftUI View declaration being deleted
	   - sourceGraph: The Periphery SourceGraph containing all declarations and references

	 - Returns: Array of implicit Declaration objects representing #Preview macros that reference the View.
	            Each returned declaration has `.isImplicit == true` and a `.location` pointing to
	            where the `#Preview` macro appears in source code.
	 */
	nonisolated static func findPreviewsForView(
		viewDeclaration: Declaration,
		sourceGraph: SourceGraph
	) -> [Declaration] {
		// Step 1: Find all #Preview macro expansions by looking for references to PreviewRegistry
		let macroReferences = sourceGraph.references(to: previewRegistryUsr)

		guard !macroReferences.isEmpty else {
			// No #Preview macros in this project
			return []
		}

		// Step 2: Extract the implicit preview declarations (parents of PreviewRegistry references)
		let previewDeclarations = macroReferences.compactMap { reference -> Declaration? in
			guard let parent = reference.parent, parent.isImplicit else {
				return nil
			}
			return parent
		}

		guard !previewDeclarations.isEmpty else {
			return []
		}

		// Step 3: Find which previews reference the View being deleted
		let viewUsrs = viewDeclaration.usrs

		let matchingPreviews = previewDeclarations.filter { previewDecl in
			// Check if this preview's references include the View
			previewDecl.references.contains { ref in
				viewUsrs.contains(ref.usr)
			}
		}

		return matchingPreviews
	}
}
