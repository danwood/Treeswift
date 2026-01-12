//
//  TreeDisplayHelpers.swift
//  Treeswift
//
//  Shared constants and helpers for tree view layouts
//

import SwiftUI

/**
Displays chevron for expandable nodes or placeholder for leaf nodes
*/
struct ChevronOrPlaceholder: View {
	let hasChildren: Bool
	@Binding var expandedIDs: Set<String>
	let id: String
	let toggleWithDescendants: () -> Void
	@Environment(\.treeLayoutSettings) private var layoutSettings

	var body: some View {
		if hasChildren {
			ChevronExpansionButton(
				expandedIDs: $expandedIDs,
				id: id,
				toggleWithDescendants: toggleWithDescendants
			)
		} else {
			Color.clear.frame(width: layoutSettings.leafNodeOffset, height: 1)
		}
	}
}

/**
View modifier for consistent tree row label padding
*/
private struct TreeLabelPadding: ViewModifier {
	let indentLevel: Int
	@Environment(\.treeLayoutSettings) var layoutSettings

	func body(content: Content) -> some View {
		content
			.padding(
				.leading,
				CGFloat(indentLevel) * layoutSettings.indentPerLevel
			)
			.padding(.vertical, layoutSettings.rowVerticalPadding)
	}
}

extension View {
	// Applies standard tree label padding based on indent level
	func treeLabelPadding(indentLevel: Int) -> some View {
		modifier(TreeLabelPadding(indentLevel: indentLevel))
	}
}
