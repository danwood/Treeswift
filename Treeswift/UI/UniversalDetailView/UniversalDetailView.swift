//
//  UniversalDetailView.swift
//  Treeswift
//
//  Universal detail panel router that shows appropriate content based on active tab
//

import PeripheryKit
import SourceGraph
import SwiftUI

struct UniversalDetailView: View {
	let selectedTab: ResultsTab
	let peripheryNode: TreeNode?
	let filesNode: FileBrowserNode?
	let categoriesNode: CategoriesNode?
	let projectPath: String?
	let hasResults: Bool
	let scanResults: [ScanResult]
	let sourceGraph: SourceGraph?
	@Binding var filterState: FilterState

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				if !hasResults {
					WelcomeEmptyStateView()
				} else {
					switch selectedTab {
					case .periphery:
						if let node = peripheryNode {
							PeripheryDetailView(
								node: node,
								scanResults: scanResults,
								sourceGraph: sourceGraph,
								projectPath: projectPath,
								filterState: $filterState
							)
						} else {
							EmptySelectionView(message: "Select an item in the Periphery tab to view details")
						}

					case .tree, .viewExtensions, .shared:
						if let node = categoriesNode {
							CategoriesDetailView(node: node)
						} else {
							EmptySelectionView(message: "Select an item to view details")
						}
					}
				}
			}
			.padding(20)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.background(Color(nsColor: .controlBackgroundColor))
	}
}

// Generic empty selection view
private struct EmptySelectionView: View {
	let message: String

	var body: some View {
		VStack(spacing: 12) {
			Text("No Selection")
				.font(.title2)
				.foregroundStyle(.secondary)
			Text(message)
				.font(.body)
				.foregroundStyle(.tertiary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding(40)
	}
}
