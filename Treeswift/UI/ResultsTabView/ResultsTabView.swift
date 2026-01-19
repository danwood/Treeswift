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
			.tabItem {
				Label("Periphery", systemImage: "list.bullet.indent")
			}
			.tag(ResultsTab.periphery)

			// Tree Tab
			Group {
				if treeSection == nil {
					ProgressView("Building Tree…")
						.padding()
				} else {
					SingleCategoryTabView(
						section: treeSection,
						showOnlyViews: $showOnlyViews,
						selectedID: $treeTabSelectedID,
						projectRootPath: projectPath.map { ($0 as NSString).deletingLastPathComponent },
						showToggle: true
					)
					.padding()
				}
			}
			.frame(maxHeight: .infinity, alignment: .top)
			.tabItem {
				Label("Tree", systemImage: "tree")
			}
			.tag(ResultsTab.tree)

			// View Extensions Tab
			Group {
				if viewExtensionsSection == nil {
					ProgressView("Building View Extensions…")
						.padding()
				} else {
					SingleCategoryTabView(
						section: viewExtensionsSection,
						showOnlyViews: $showOnlyViews,
						selectedID: $viewExtensionsTabSelectedID,
						projectRootPath: projectPath.map { ($0 as NSString).deletingLastPathComponent },
						showToggle: false
					)
					.padding()
				}
			}
			.frame(maxHeight: .infinity, alignment: .top)
			.tabItem {
				Label("View Extensions", systemImage: "puzzlepiece.extension")
			}
			.tag(ResultsTab.viewExtensions)

			// Shared Tab
			Group {
				if sharedSection == nil {
					ProgressView("Building Shared…")
						.padding()
				} else {
					SingleCategoryTabView(
						section: sharedSection,
						showOnlyViews: $showOnlyViews,
						selectedID: $sharedTabSelectedID,
						projectRootPath: projectPath.map { ($0 as NSString).deletingLastPathComponent },
						showToggle: false
					)
					.padding()
				}
			}
			.frame(maxHeight: .infinity, alignment: .top)
			.tabItem {
				Label("Shared", systemImage: "square.stack.3d.up")
			}
			.tag(ResultsTab.shared)
		}
		.frame(minHeight: 400)
	}
}
