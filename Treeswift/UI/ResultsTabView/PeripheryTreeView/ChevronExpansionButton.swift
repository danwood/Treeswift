//
//  ChevronExpansionButton.swift
//  Treeswift
//
//  Reusable chevron expansion button for tree views
//

import SwiftUI

struct ChevronExpansionButton: View {
	@Binding var expandedIDs: Set<String>
	let id: String
	let toggleWithDescendants: () -> Void
	@Environment(\.treeLayoutSettings) private var layoutSettings

	private var isExpanded: Bool {
		expandedIDs.contains(id)
	}

	var body: some View {
		Button {
			if expandedIDs.contains(id) {
				expandedIDs.remove(id)
			} else {
				expandedIDs.insert(id)
			}
		} label: {
			Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
				.font(.caption2)
				.foregroundStyle(.secondary)
				.frame(width: layoutSettings.chevronWidth)
				.padding(4)
				.contentShape(.rect)
		}
		.buttonStyle(.plain)
		.simultaneousGesture(
			TapGesture(count: 1)
				.modifiers(.option)
				.onEnded {
					toggleWithDescendants()
				}
		)
		.accessibilityLabel(isExpanded ? "Collapse" : "Expand")
	}
}
