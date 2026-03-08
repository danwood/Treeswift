//
//  ResultsTabView.swift
//  Treeswift
//
//  Tabbed view for displaying scan results in multiple formats
//

import PeripheryKit
import SourceGraph
import SwiftUI

enum ResultsTab: String, CaseIterable, Sendable {
	case periphery
	case tree
	case viewExtensions
	case shared
}

extension EnvironmentValues {
	@Entry var refreshFileTree: (() -> Void)?
	@Entry var peripheryFilterState: FilterState?
}

struct ResultsTabView: View {
	let treeNodes: [TreeNode]
	let scanResults: [ScanResult]
	let sourceGraph: SourceGraph?
	let treeSection: CategoriesNode?
	let viewExtensionsSection: CategoriesNode?
	let sharedSection: CategoriesNode?
	let orphansSection: CategoriesNode?
	let previewOrphansSection: CategoriesNode?
	let bodyGetterSection: CategoriesNode?
	let unattachedSection: CategoriesNode?
	let fileTreeNodes: [FileBrowserNode]
	let projectPath: String?

	@Binding var filterState: FilterState
	@AppStorage("showOnlyViews") private var showOnlyViews: Bool = false
	@AppStorage("showFileInfo") private var showFileInfo: Bool = false
	@AppStorage("showCodeSize") private var showCodeSize: Bool = false
	@AppStorage("showPath") private var showPath: Bool = false
	@AppStorage("showFileName") private var showFileName: Bool = false
	@AppStorage("showConformance") private var showConformance: Bool = false
	@AppStorage("selectedResultsTab") private var selectedTab: ResultsTab = .periphery
	@Binding var peripheryTabSelectedID: String?
	@Binding var filesTabSelectedID: String?
	@Binding var treeTabSelectedID: String?
	@Binding var viewExtensionsTabSelectedID: String?
	@Binding var sharedTabSelectedID: String?
	@Binding var orphansTabSelectedID: String?
	@Binding var previewOrphansTabSelectedID: String?
	@Binding var bodyGetterTabSelectedID: String?
	@Binding var unattachedTabSelectedID: String?

	var body: some View {
		TabView(selection: $selectedTab) {
			Tab("Periphery", systemImage: "list.bullet.indent", value: ResultsTab.periphery) {
				// Periphery Tab - Results Tree
				VStack(alignment: .leading, spacing: 12) {
					if !scanResults.isEmpty {
						FilterBarView(filterState: filterState, scanResults: scanResults)
							.padding(.horizontal)
					}

					Group {
						if treeNodes.isEmpty, !scanResults.isEmpty {
							ProgressView("Building tree view…")
								.frame(maxWidth: .infinity)
								.padding()
						} else {
							PeripheryTreeView(
								rootNodes: treeNodes,
								scanResults: scanResults,
								sourceGraph: sourceGraph,
								filterState: filterState,
								selectedID: $peripheryTabSelectedID
							)
							.padding()
						}
					}
				}
				.frame(maxHeight: .infinity, alignment: .top)
			}

			Tab("Tree", systemImage: "tree", value: ResultsTab.tree) {
				CategoryTab(
					section: treeSection,
					progressLabel: "Building Tree…",
					showOnlyViews: $showOnlyViews,
					showFileName: $showFileName,
					showFileInfo: $showFileInfo,
					showCodeSize: $showCodeSize,
					showPath: $showPath,
					showConformance: $showConformance,
					selectedID: $treeTabSelectedID,
					projectRootPath: projectPath.map { ($0 as NSString).deletingLastPathComponent },
					showToggle: true
				)
				.frame(maxHeight: .infinity, alignment: .top)
			}

			Tab("View Extensions", systemImage: "puzzlepiece.extension", value: ResultsTab.viewExtensions) {
				CategoryTab(
					section: viewExtensionsSection,
					progressLabel: "Building View Extensions…",
					showOnlyViews: $showOnlyViews,
					showFileName: $showFileName,
					showFileInfo: $showFileInfo,
					showCodeSize: $showCodeSize,
					showPath: $showPath,
					showConformance: $showConformance,
					selectedID: $viewExtensionsTabSelectedID,
					projectRootPath: projectPath.map { ($0 as NSString).deletingLastPathComponent },
					showToggle: true
				)
				.frame(maxHeight: .infinity, alignment: .top)
			}

			Tab("Shared", systemImage: "square.stack.3d.up", value: ResultsTab.shared) {
				CategoryTab(
					section: sharedSection,
					progressLabel: "Building Shared…",
					showOnlyViews: $showOnlyViews,
					showFileName: $showFileName,
					showFileInfo: $showFileInfo,
					showCodeSize: $showCodeSize,
					showPath: $showPath,
					showConformance: $showConformance,
					selectedID: $sharedTabSelectedID,
					projectRootPath: projectPath.map { ($0 as NSString).deletingLastPathComponent },
					showToggle: true
				)
				.frame(maxHeight: .infinity, alignment: .top)
			}
		}
		.frame(minHeight: 400)
	}
}

private struct CategoryTab: View {
	let section: CategoriesNode?
	let progressLabel: String
	@Binding var showOnlyViews: Bool
	@Binding var showFileName: Bool
	@Binding var showFileInfo: Bool
	@Binding var showCodeSize: Bool
	@Binding var showPath: Bool
	@Binding var showConformance: Bool
	@Binding var selectedID: String?
	var projectRootPath: String?
	let showToggle: Bool

	var body: some View {
		if let section {
			SingleCategoryTabView(
				section: section,
				showOnlyViews: $showOnlyViews,
				showFileName: $showFileName,
				showFileInfo: $showFileInfo,
				showCodeSize: $showCodeSize,
				showPath: $showPath,
				showConformance: $showConformance,
				selectedID: $selectedID,
				projectRootPath: projectRootPath,
				showToggle: showToggle
			)
			.padding()
		} else {
			ProgressView(progressLabel)
				.padding()
		}
	}
}
