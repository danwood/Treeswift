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
	@Environment(FileInspectorState.self) private var inspectorState

	init() {
		self._scanStateManager = State(initialValue: ScanStateManager())
	}

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

	private var selectedPeripheryNode: TreeNode? {
		guard let selectedID = peripheryTabSelectedID,
			  let scanState = currentScanState else { return nil }
		return findPeripheryNode(withID: selectedID, in: scanState.treeNodes)
	}

	private var selectedFilesNode: FileBrowserNode? {
		guard let selectedID = filesTabSelectedID,
			  let scanState = currentScanState else { return nil }
		return scanState.fileNodesLookup[selectedID]
	}

	private var selectedCategoriesNode: CategoriesNode? {
		guard let scanState = currentScanState else { return nil }
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
			return nil
		}

		guard let id = selectedID, let sect = section else { return nil }
		return findCategoriesNode(withID: id, in: [sect])
	}

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			SidebarView(
				configManager: configManager,
				scanStateManager: scanStateManager,
				selectedConfigID: selectedConfigID
			)
			.navigationSplitViewColumnWidth(min: LayoutConstants.sidebarMinWidth, ideal: LayoutConstants.sidebarIdealWidth, max: LayoutConstants.sidebarMaxWidth)
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
					unattachedTabSelectedID: $unattachedTabSelectedID
				)
				.navigationSplitViewColumnWidth(min: LayoutConstants.contentColumnMinWidth, ideal: LayoutConstants.contentColumnIdealWidth, max: LayoutConstants.contentColumnMaxWidth)
			}
		} detail: {
			if let scanState = currentScanState {
				UniversalDetailView(
					selectedTab: selectedTab,
					peripheryNode: selectedPeripheryNode,
					filesNode: selectedFilesNode,
					categoriesNode: selectedCategoriesNode,
					projectPath: scanState.projectPath,
					hasResults: !scanState.scanResults.isEmpty || scanState.sourceGraph != nil,
					scanResults: scanState.scanResults,
					sourceGraph: scanState.sourceGraph,
					filterState: $filterState
				)
				.navigationSplitViewColumnWidth(min: LayoutConstants.detailColumnMinWidth, ideal: LayoutConstants.detailColumnIdealWidth, max: LayoutConstants.detailColumnMaxWidth)
			} else {
				UniversalDetailView(
					selectedTab: selectedTab,
					peripheryNode: nil,
					filesNode: nil,
					categoriesNode: nil,
					projectPath: nil,
					hasResults: false,
					scanResults: [],
					sourceGraph: nil,
					filterState: $filterState
				)
				.navigationSplitViewColumnWidth(min: LayoutConstants.detailColumnMinWidth, ideal: LayoutConstants.detailColumnIdealWidth, max: LayoutConstants.detailColumnMaxWidth)
			}
		}
		.environment(\.treeLayoutSettings, layoutSettings)
		.onAppear {
			if selectedConfigID.wrappedValue == nil, let firstConfig = configManager.configurations.first {
				selectedConfigID.wrappedValue = firstConfig.id
			}
		}
		.onChange(of: filesTabSelectedID) { _, newID in
			updateInspectorState(forFilesSelection: newID)
		}
		.onChange(of: peripheryTabSelectedID) { _, newID in
			updateInspectorState(forPeripherySelection: newID)
		}
	}

	/*
	 Updates the inspector state when a file is selected in the Files tab
	 */
	private func updateInspectorState(forFilesSelection selectedID: String?) {
		guard let selectedID = selectedID,
			  let scanState = currentScanState,
			  case .file(let file) = scanState.fileNodesLookup[selectedID] else {
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
		guard let selectedID = selectedID,
			  let scanState = currentScanState,
			  let node = findPeripheryNode(withID: selectedID, in: scanState.treeNodes),
			  case .file(let file) = node else {
			inspectorState.clearInspectedFile()
			return
		}

		// Get file metadata from fileNodesLookup if available
		if case .file(let browserFile) = scanState.fileNodesLookup[file.path] {
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
			case .folder(let folder):
				if folder.id == id { return node }
				if let found = findPeripheryNode(withID: id, in: folder.children) { return found }
			case .file(let file):
				if file.id == id { return node }
			}
		}
		return nil
	}

	private func findCategoriesNode(withID id: String, in nodes: [CategoriesNode]) -> CategoriesNode? {
		for node in nodes {
			switch node {
			case .section(let section):
				if section.id.rawValue == id { return node }
				if let found = findCategoriesNode(withID: id, in: section.children) { return found }
			case .declaration(let decl):
				if decl.id == id { return node }
				if let found = findCategoriesNode(withID: id, in: decl.children) { return found }
			case .syntheticRoot(let root):
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
