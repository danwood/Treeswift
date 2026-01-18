//
//  TreeExpansionHelper.swift
//  Treeswift
//
//  Shared utilities for tree expansion state management
//

import SwiftUI

// Extension providing tree expansion utilities for Set<String>
extension Set<String> {
	// Toggles expansion for an ID and optionally all its descendants
	mutating func toggleExpansion(
		id: String,
		withDescendants: Bool = false,
		collectDescendants: (() -> Set<String>)? = nil
	) {
		let isExpanded = contains(id)

		if isExpanded {
			remove(id)
			if withDescendants, let descendants = collectDescendants?() {
				subtract(descendants)
			}
		} else {
			insert(id)
			if withDescendants, let descendants = collectDescendants?() {
				formUnion(descendants)
			}
		}
	}
}

// Helper to create expansion binding from Set<String>
func expansionBinding(for id: String, in expandedIDs: Binding<Set<String>>) -> Binding<Bool> {
	Binding(
		get: { expandedIDs.wrappedValue.contains(id) },
		set: { isExpanded in
			if isExpanded {
				expandedIDs.wrappedValue.insert(id)
			} else {
				expandedIDs.wrappedValue.remove(id)
			}
		}
	)
}

// Custom DisclosureGroup style that hides the default disclosure indicator
struct TreeDisclosureStyle: DisclosureGroupStyle {
	func makeBody(configuration: Configuration) -> some View {
		VStack(alignment: .leading, spacing: 0) {
			configuration.label
			if configuration.isExpanded {
				configuration.content
			}
		}
	}
}
