//
//  SearchSuggestionRow.swift
//  Treeswift
//
//  Individual result row for toolbar search suggestions.
//  Shows match type icon, name, tab badge, and file/symbol label.
//

import SwiftUI

/* folderprivate */ struct SearchSuggestionRow: View {
	let result: SearchMatchEngine.SearchResult
	let isCurrentTab: Bool

	var body: some View {
		HStack(spacing: 6) {
			result.icon.view(size: 16)

			Text(result.name)
				.lineLimit(1)

			Spacer()

			if !isCurrentTab {
				Text(result.tab.displayName)
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.horizontal, 5)
					.padding(.vertical, 1)
					.background(.quaternary)
					.clipShape(.rect(cornerRadius: 3))
			}
		}
	}
}
