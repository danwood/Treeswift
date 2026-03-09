//
//  ContentView.swift
//  Treeswift
//
//  Main view with three-column navigation: sidebar, content, and detail
//

import SwiftUI

struct ContentView: View {
	@State private var configManager = ConfigurationManager()
	@State private var scanStateManager: ScanStateManager
	@AppStorage("selectedConfigID") private var selectedConfigIDString: String = ""
	@AppStorage("selectedResultsTab") private var selectedTab: ResultsTab = .periphery
	@State private var columnVisibility: NavigationSplitViewVisibility = .all

	@State private var peripheryTabSelectedID: String?
	@State private var filesTabSelectedID: String?
	@State private var treeTabSelectedID: String?
	@State private var viewExtensionsTabSelectedID: String?
	@State private var sharedTabSelectedID: String?
	@State private var orphansTabSelectedID: String?
	@State private var previewOrphansTabSelectedID: String?
	@State private var bodyGetterTabSelectedID: String?
	@State private var unattachedTabSelectedID: String?
	@State private var filterState = FilterState()
	@State private var layoutSettings = TreeLayoutSettings()
	@State private var selectedPeripheryNode: TreeNode?
	@State private var selectedFilesNode: FileBrowserNode?
	@State private var selectedCategoriesNode: CategoriesNode?
	@State private var searchNavState = SearchNavigationState()
	@State private var searchResults: [SearchMatchEngine.SearchResult] = []
	@AppStorage("showOnlyViews") private var showOnlyViews: Bool = false
	@Environment(FileInspectorState.self) private var inspectorState

	init() {
		_scanStateManager = State(initialValue: ScanStateManager())
	}

	// Binding(get:set:) is intentional here — @AppStorage cannot store UUID? natively.
	// A retroactive RawRepresentable conformance on Optional<UUID> doesn't satisfy
	// AppStorage's constraints on macOS. This computed Binding is the correct pattern.
	private var selectedConfigID: Binding<UUID?> {
		Binding(
			get: {
				selectedConfigIDString.isEmpty ? nil : UUID(uuidString: selectedConfigIDString)
			},
			set: { newValue in
				selectedConfigIDString = newValue?.uuidString ?? ""
			}
		)
	}

	private var currentScanState: ScanState? {
		guard let selectedID = selectedConfigID.wrappedValue else { return nil }
		return scanStateManager.getState(for: selectedID)
	}

	private func recomputeSelectedPeripheryNode() {
		guard let selectedID = peripheryTabSelectedID,
		      let scanState = currentScanState else {
			selectedPeripheryNode = nil
			return
		}
		selectedPeripheryNode = findPeripheryNode(withID: selectedID, in: scanState.treeNodes)
	}

	private func recomputeSelectedFilesNode() {
		guard let selectedID = filesTabSelectedID,
		      let scanState = currentScanState else {
			selectedFilesNode = nil
			return
		}
		selectedFilesNode = scanState.fileNodesLookup[selectedID]
	}

	private func recomputeSelectedCategoriesNode() {
		guard let scanState = currentScanState else {
			selectedCategoriesNode = nil
			return
		}
		let selectedID: String?
		let section: CategoriesNode?

		switch selectedTab {
		case .tree:
			selectedID = treeTabSelectedID
			section = scanState.treeSection
		case .viewExtensions:
			selectedID = viewExtensionsTabSelectedID
			section = scanState.viewExtensionsSection
		case .shared:
			selectedID = sharedTabSelectedID
			section = scanState.sharedSection
		default:
			selectedCategoriesNode = nil
			return
		}

		guard let id = selectedID, let sect = section else {
			selectedCategoriesNode = nil
			return
		}
		selectedCategoriesNode = findCategoriesNode(withID: id, in: [sect])
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			SidebarView(
				configManager: configManager,
				scanStateManager: scanStateManager,
				selectedConfigID: selectedConfigID
			)
			.navigationSplitViewColumnWidth(
				min: LayoutConstants.sidebarMinWidth,
				ideal: LayoutConstants.sidebarIdealWidth,
				max: LayoutConstants.sidebarMaxWidth
			)
			.navigationTitle("Configurations")
		} content: {
			if let selectedID = selectedConfigID.wrappedValue,
			   let index = configManager.configurations.firstIndex(where: { $0.id == selectedID }) {
				ContentColumnView(
					configuration: $configManager.configurations[index],
					scanState: scanStateManager.getState(for: selectedID),
					onUpdate: { updatedConfig in
						configManager.updateConfiguration(at: index, with: updatedConfig)
					},
					filterState: $filterState,
					layoutSettings: $layoutSettings,
					peripheryTabSelectedID: $peripheryTabSelectedID,
					filesTabSelectedID: $filesTabSelectedID,
					treeTabSelectedID: $treeTabSelectedID,
					viewExtensionsTabSelectedID: $viewExtensionsTabSelectedID,
					sharedTabSelectedID: $sharedTabSelectedID,
					orphansTabSelectedID: $orphansTabSelectedID,
					previewOrphansTabSelectedID: $previewOrphansTabSelectedID,
					bodyGetterTabSelectedID: $bodyGetterTabSelectedID,
					unattachedTabSelectedID: $unattachedTabSelectedID,
					searchNavState: searchNavState
				)
				.navigationSplitViewColumnWidth(
					min: LayoutConstants.contentColumnMinWidth,
					ideal: LayoutConstants.contentColumnIdealWidth,
					max: LayoutConstants.contentColumnMaxWidth
				)
			}
		} detail: {
			let projectPath = currentScanState?.projectPath
			let hasResults = currentScanState.map { !$0.scanResults.isEmpty || $0.sourceGraph != nil } ?? false
			let scanResults = currentScanState?.scanResults ?? []
			let sourceGraph = currentScanState?.sourceGraph

			UniversalDetailView(
				selectedTab: selectedTab,
				peripheryNode: selectedPeripheryNode,
				filesNode: selectedFilesNode,
				categoriesNode: selectedCategoriesNode,
				projectPath: projectPath,
				hasResults: hasResults,
				scanResults: scanResults,
				sourceGraph: sourceGraph,
				filterState: $filterState
			)
			.navigationSplitViewColumnWidth(
				min: LayoutConstants.detailColumnMinWidth,
				ideal: LayoutConstants.detailColumnIdealWidth,
				max: LayoutConstants.detailColumnMaxWidth
			)
		}
		.environment(\.treeLayoutSettings, layoutSettings)
		.searchable(
			text: $searchNavState.toolbarSearchQuery,
			isPresented: $searchNavState.isSearchPresented,
			placement: .toolbar
		)
		.searchSuggestions {
			if !searchResults.isEmpty {
				let currentTabResults = searchResults.filter { $0.tab == selectedTab }
				let otherTabResults = searchResults.filter { $0.tab != selectedTab }

				if !currentTabResults.isEmpty {
					ForEach(currentTabResults.prefix(12)) { result in
						Button {
							navigateToResult(result)
						} label: {
							SearchSuggestionRow(result: result, isCurrentTab: true)
						}
					}
				}

				if !otherTabResults.isEmpty {
					if !currentTabResults.isEmpty {
						Divider()
					}
					ForEach(otherTabResults.prefix(8)) { result in
						Button {
							navigateToResult(result)
						} label: {
							SearchSuggestionRow(result: result, isCurrentTab: false)
						}
					}
				}
			}
		}
		.onChange(of: searchNavState.toolbarSearchQuery) {
			updateSearchResults()
		}
		.onChange(of: showOnlyViews) {
			updateSearchResults()
		}
		.onSubmit(of: .search) {
			handleSearchSubmit()
		}
		.onAppear {
			// Handle initial configuration selection
			if selectedConfigID.wrappedValue == nil, let firstConfig = configManager.configurations.first {
				selectedConfigID.wrappedValue = firstConfig.id
			}

			// Check for --scan launch argument
			let launchMode = LaunchArgumentsHandler.parseLaunchMode()
			if case let .gui(scanConfiguration: configName?) = launchMode {
				handleScanArgument(configName: configName)
			}

			recomputeSelectedPeripheryNode()
			recomputeSelectedFilesNode()
			recomputeSelectedCategoriesNode()
		}
		.onChange(of: peripheryTabSelectedID) { _, newID in
			recomputeSelectedPeripheryNode()
			updateInspectorState(forPeripherySelection: newID)
		}
		.onChange(of: filesTabSelectedID) { _, newID in
			recomputeSelectedFilesNode()
			updateInspectorState(forFilesSelection: newID)
		}
		.onChange(of: treeTabSelectedID) {
			recomputeSelectedCategoriesNode()
		}
		.onChange(of: viewExtensionsTabSelectedID) {
			recomputeSelectedCategoriesNode()
		}
		.onChange(of: sharedTabSelectedID) {
			recomputeSelectedCategoriesNode()
		}
		.onChange(of: selectedTab) {
			recomputeSelectedCategoriesNode()
		}
		.focusedSceneValue(\.activateSearch) { [searchNavState] in
			searchNavState.isSearchPresented = true
		}
	}

	// MARK: - Toolbar Search

	/**
	 Searches across all tabs using SearchMatchEngine and updates the search results.
	 Current tab results are sorted first by the suggestion UI.
	 */
	private func updateSearchResults() {
		let query = searchNavState.toolbarSearchQuery
		guard query.count >= 3, let scanState = currentScanState else {
			searchResults = []
			return
		}

		var allResults: [SearchMatchEngine.SearchResult] = []

		// Search Periphery tab (TreeNode hierarchy) — always searches all nodes
		allResults.append(contentsOf: SearchMatchEngine.searchTreeNodes(
			query,
			in: scanState.treeNodes,
			expandedIDs: [],
			visibleOnly: false
		))

		// Search category tabs — always searches all nodes
		let categoryTabs: [(ResultsTab, CategoriesNode?)] = [
			(.tree, scanState.treeSection),
			(.viewExtensions, scanState.viewExtensionsSection),
			(.shared, scanState.sharedSection)
		]
		for (tab, section) in categoryTabs {
			allResults.append(contentsOf: SearchMatchEngine.searchCategoriesNodes(
				query,
				in: section,
				tab: tab,
				expandedIDs: [],
				visibleOnly: false
			))
		}

		// Deduplicate by normalized name: strip .swift extension so that
		// "Foo" (symbol) and "Foo.swift" (file) are treated as the same entry.
		// Prefer symbol matches over file matches, and current tab over other tabs.
		var seenNames = Set<String>()
		let sorted = allResults.sorted { lhs, rhs in
			let lhsCurrent = lhs.tab == selectedTab
			let rhsCurrent = rhs.tab == selectedTab
			if lhsCurrent != rhsCurrent { return lhsCurrent }
			// Prefer symbol matches over file matches
			if lhs.matchType != rhs.matchType {
				return lhs.matchType == .symbolName
			}
			return lhs < rhs
		}
		searchResults = sorted.filter { result in
			// When "Views Only" is enabled, skip non-view declarations
			if showOnlyViews, result.isView == false {
				return false
			}
			return seenNames.insert(deduplicationKey(result.name)).inserted
		}
	}

	// Strips .swift extension and lowercases so "Foo" and "Foo.swift" produce the same key.
	private func deduplicationKey(_ name: String) -> String {
		if name.hasSuffix(".swift") {
			String(name.dropLast(6)).lowercased()
		} else {
			name.lowercased()
		}
	}

	/**
	 Navigates to a specific search result by switching tabs if needed
	 and posting a navigation request for the target tree view.
	 */
	private func navigateToResult(_ result: SearchMatchEngine.SearchResult) {
		// Switch tab if needed
		if selectedTab != result.tab {
			selectedTab = result.tab
		}

		// Set the appropriate per-tab selectedID
		switch result.tab {
		case .periphery:
			peripheryTabSelectedID = result.nodeID
		case .tree:
			treeTabSelectedID = result.nodeID
		case .viewExtensions:
			viewExtensionsTabSelectedID = result.nodeID
		case .shared:
			sharedTabSelectedID = result.nodeID
		}

		// Post navigation request for the tree view to handle expansion and scrolling
		searchNavState.navigationRequest = SearchNavigationState.NavigationRequest(
			targetTab: result.tab,
			targetNodeID: result.nodeID,
			parentIDsToExpand: result.parentIDs
		)

		// Clear the search query
		searchNavState.toolbarSearchQuery = ""
		searchResults = []
	}

	/**
	 Handles search submission (pressing Enter in the search field).
	 Navigates to the first matching result if available.
	 */
	private func handleSearchSubmit() {
		// Prefer current tab results, then any result
		let currentTabResult = searchResults.first { $0.tab == selectedTab }
		if let result = currentTabResult ?? searchResults.first {
			navigateToResult(result)
		}
	}

	/**
	 Handles the --scan launch argument by finding and selecting the configuration,
	 then starting a scan.
	 */
	private func handleScanArgument(configName: String) {
		// Find configuration matching the display name
		var foundConfig: PeripheryConfiguration?
		for config in configManager.configurations {
			guard let projectPath = config.project else { continue }

			// Use same display name logic as --list
			let url = URL(fileURLWithPath: projectPath)
			let displayName: String = switch config.projectType {
			case .xcode:
				url.deletingPathExtension().lastPathComponent
			case .swiftPackage:
				url.deletingLastPathComponent().lastPathComponent
			}

			if displayName == configName {
				foundConfig = config
				break
			}
		}

		// Fallback: try internal configuration name
		if foundConfig == nil {
			foundConfig = configManager.configurations.first(where: { $0.name == configName })
		}

		guard let config = foundConfig else {
			fputs("Error: Configuration not found: '\(configName)'\n", stderr)
			fputs("Use --list to see available configurations\n", stderr)
			return
		}

		// Select the configuration
		selectedConfigID.wrappedValue = config.id

		// Start the scan
		let scanState = scanStateManager.getState(for: config.id)
		scanState.startScan(configuration: config)

		fputs("Started scan for configuration: \(configName)\n", stderr)
	}

	/*
	 Updates the inspector state when a file is selected in the Files tab
	 */
	private func updateInspectorState(forFilesSelection selectedID: String?) {
		guard let selectedID,
		      let scanState = currentScanState,
		      case let .file(file) = scanState.fileNodesLookup[selectedID] else {
			inspectorState.clearInspectedFile()
			return
		}

		inspectorState.setInspectedFile(
			filePath: file.path,
			modificationDate: file.modificationDate,
			fileSize: file.fileSize
		)
	}

	/*
	 Updates the inspector state when a file is selected in the Periphery tab
	 */
	private func updateInspectorState(forPeripherySelection selectedID: String?) {
		guard let selectedID,
		      let scanState = currentScanState,
		      let node = findPeripheryNode(withID: selectedID, in: scanState.treeNodes),
		      case let .file(file) = node else {
			inspectorState.clearInspectedFile()
			return
		}

		// Get file metadata from fileNodesLookup if available
		if case let .file(browserFile) = scanState.fileNodesLookup[file.path] {
			inspectorState.setInspectedFile(
				filePath: file.path,
				modificationDate: browserFile.modificationDate,
				fileSize: browserFile.fileSize
			)
		} else {
			// Fallback: just set the path without metadata
			inspectorState.setInspectedFile(
				filePath: file.path,
				modificationDate: nil,
				fileSize: nil
			)
		}
	}

	private func findPeripheryNode(withID id: String, in nodes: [TreeNode]) -> TreeNode? {
		for node in nodes {
			switch node {
			case let .folder(folder):
				if folder.id == id { return node }
				if let found = findPeripheryNode(withID: id, in: folder.children) { return found }
			case let .file(file):
				if file.id == id { return node }
			}
		}
		return nil
	}

	private func findCategoriesNode(withID id: String, in nodes: [CategoriesNode]) -> CategoriesNode? {
		for node in nodes {
			switch node {
			case let .section(section):
				if section.id.rawValue == id { return node }
				if let found = findCategoriesNode(withID: id, in: section.children) { return found }
			case let .declaration(decl):
				if decl.id == id { return node }
				if let found = findCategoriesNode(withID: id, in: decl.children) { return found }
			case let .syntheticRoot(root):
				if root.id == id { return node }
				if let found = findCategoriesNode(withID: id, in: root.children) { return found }
			}
		}
		return nil
	}
}

#Preview {
	ContentView()
}
