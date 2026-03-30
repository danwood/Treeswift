//
//  PeripheryTreeView.swift
//  Treeswift
//
//  Hierarchical tree view for scan results
//

import AppKit
import PeripheryKit
import SourceGraph
import SwiftUI
import SystemPackage

private struct OperationError: Identifiable {
	let id = UUID()
	let message: String
}

struct PeripheryTreeView: View {
	let rootNodes: [TreeNode]
	let scanResults: [ScanResult]
	let sourceGraph: SourceGraph?
	let filterState: FilterState?
	@Binding var selectedID: String?
	var searchNavState: SearchNavigationState
	@State private var expandedIDs: Set<String> = []
	@State private var hasAppearedOnce: Bool = false
	@State private var claimFocusTrigger: Bool = false
	@State private var filteredNodesCache: [TreeNode] = []
	@State private var hiddenFileIDs: Set<String> = []
	@State private var removingFileIDs: Set<String> = []
	@State private var hiddenWarningIDs: Set<String> = []
	@State private var fileOperationProgress = FileOperationProgressState()
	@State private var showProgressSheet = false
	@State private var resultIndex = ScanResultIndex()
	@State private var cachedVisibleItems: [String] = []
	@State private var removalSummary: RemovalSummary?
	@State private var operationError: OperationError?
	@State private var showStrategySheet = false
	@State private var pendingRemovalTarget: RemovalTarget?
	@State private var pendingDependencyChains: [DependencyChain] = []
	@State private var typeAheadState = TypeAheadState()
	@AppStorage("typeAheadSearchAllNodes") private var typeAheadSearchAllNodes: Bool = false
	@Environment(\.undoManager) private var undoManager

	/**
	 Target for a pending removal operation (file or folder).
	 */
	private enum RemovalTarget {
		case file(FileNode)
		case folder(FolderNode)
	}

	/**
	 Summary of deletion operations for alert display.
	 */
	private struct RemovalSummary: Identifiable {
		let id = UUID()
		let deletedCount: Int
		let nonDeletableCount: Int
		let failedIgnoreCommentsCount: Int
		let skippedReferencedCount: Int
		let fileCount: Int
		let targetName: String
	}

	fileprivate static let removeUnusedCodeLabel = "Remove Unused Code…"

	var body: some View {
		// Force dependency on filterChangeCounter by accessing it in body

		ScrollViewReader { scrollProxy in
			LazyVStack(alignment: .leading, spacing: 0) {
				ForEach(filteredNodesCache, id: \.id) { node in
					TreeNodeView(
						node: node,
						filterState: filterState,
						scanResults: scanResults,
						expandedIDs: $expandedIDs,
						selectedID: $selectedID,
						removingFileIDs: $removingFileIDs,
						hiddenWarningIDs: hiddenWarningIDs,
						resultIndex: resultIndex,
						onIgnoreAllWarnings: ignoreAllWarnings,
						onRemoveAllUnusedCode: requestRemoveUnusedCode,
						onIgnoreAllWarningsInFolder: ignoreAllWarningsInFolder,
						onRemoveAllUnusedCodeInFolder: requestRemoveUnusedCodeInFolder,
						copyMenuLabel: copyMenuLabel,
						copyPathMenuLabel: copyPathMenuLabel,
						copyFilePathsToClipboard: copyFilePathsToClipboard
					)
					.frame(maxWidth: .infinity, alignment: .leading)
				}
			}
			.focusableTreeNavigation(
				selectedID: $selectedID,
				visibleItems: cachedVisibleItems,
				claimFocusTrigger: $claimFocusTrigger,
				onCharacterKey: { chars in
					handleTypeAheadCharacter(chars, scrollProxy: scrollProxy)
				}
			)
			.focusedValue(\.copyableText, currentCopyableText(from: filteredNodesCache))
			.focusedValue(\.copyMenuTitle, "Copy Periphery Warnings")
			.onCopyCommand {
				guard let text = currentCopyableText(from: filteredNodesCache) else { return [] }
				return [NSItemProvider(object: text as NSString)]
			}
			.onAppear {
				resultIndex.rebuild(from: scanResults)
				recomputeFilteredNodes()
				rebuildVisibleItemsCache()
				// Only expand on first appearance to avoid re-expanding when switching tabs
				if expandedIDs.isEmpty {
					expandToFileLevel(using: rootNodes)
				}
			}
			.task {
				guard !hasAppearedOnce else { return }
				hasAppearedOnce = true
				try? await Task.sleep(for: .milliseconds(50))
				claimFocusTrigger.toggle()
			}
			.onChange(of: rootNodes) {
				recomputeFilteredNodes()
			}
			.onChange(of: filterState?.filterChangeCounter) { _, _ in
				resultIndex.invalidateCache(for: filterState)
				recomputeFilteredNodes()
			}
			.onChange(of: scanResults) {
				resultIndex.rebuild(from: scanResults)
				recomputeFilteredNodes()
			}
			.onChange(of: hiddenFileIDs) {
				recomputeFilteredNodes()
			}
			.onChange(of: hiddenWarningIDs) {
				recomputeFilteredNodes()
			}
			.onChange(of: filteredNodesCache) {
				rebuildVisibleItemsCache()
			}
			.onChange(of: expandedIDs) {
				rebuildVisibleItemsCache()
			}
			.task {
				// NotificationCenter.notifications(named:) returns an AsyncSequence that is
				// automatically cancelled when the task is cancelled (view disappears),
				// making this superior to onReceive for structured concurrency participation.
				for await notification in NotificationCenter.default.notifications(
					named: Notification.Name("PeripheryWarningCompleted")
				) {
					if let warningID = notification.object as? String {
						hiddenWarningIDs.insert(warningID)
					}
				}
			}
			.task {
				for await notification in NotificationCenter.default.notifications(
					named: Notification.Name("PeripheryWarningRestored")
				) {
					if let warningID = notification.object as? String {
						hiddenWarningIDs.remove(warningID)
					}
				}
			}
			.sheet(isPresented: $showProgressSheet) {
				FileOperationProgressSheet(
					progressState: fileOperationProgress,
					onCancel: {
						fileOperationProgress.isCancelled = true
					}
				)
				.interactiveDismissDisabled()
			}
			.sheet(isPresented: $showStrategySheet) {
				RemovalStrategySheet(
					targetName: pendingRemovalTargetName,
					dependencyChains: pendingDependencyChains,
					onConfirm: { strategy in
						showStrategySheet = false
						if let target = pendingRemovalTarget {
							executePendingRemoval(target: target, strategy: strategy)
						}
					},
					onCancel: {
						showStrategySheet = false
						pendingRemovalTarget = nil
						pendingDependencyChains = []
					}
				)
			}
			.alert(item: $removalSummary) { summary in
				Alert(
					title: Text("Deletion Summary"),
					message: Text(buildSummaryMessage(summary)),
					dismissButton: .default(Text("OK"))
				)
			}
			// Binding(get:set:) is intentional — macOS SwiftUI does not expose the
			// .alert(item:) overload that iOS has, so isPresented with a manual binding
			// is the only way to drive an alert from an optional model value on macOS.
			.alert(
				"Operation Failed",
				isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })
			) {
				Text(operationError?.message ?? "")
			}
			.onChange(of: searchNavState.navigationRequest) {
				handleNavigationRequest(scrollProxy: scrollProxy)
			}
		} // ScrollViewReader
	}

	private func recomputeFilteredNodes() {
		let newFiltered: [TreeNode] = if let filterState {
			rootNodes.compactMap { filterNode($0, with: filterState) }
		} else {
			rootNodes
		}
		// Always update - SwiftUI will handle diff efficiently
		filteredNodesCache = newFiltered
	}

	private func rebuildVisibleItemsCache() {
		cachedVisibleItems = TreeKeyboardNavigation.buildVisibleItemList(
			nodes: filteredNodesCache,
			expandedIDs: expandedIDs
		)
	}

	/**
	 Handles a typed character for Finder-style type-ahead search.
	 Accumulates characters in the buffer and selects the first matching node.
	 */
	private func handleTypeAheadCharacter(_ chars: String, scrollProxy: ScrollViewProxy) {
		typeAheadState.appendCharacter(chars) { query in
			let results = SearchMatchEngine.searchTreeNodes(
				query,
				in: filteredNodesCache,
				expandedIDs: expandedIDs,
				visibleOnly: !typeAheadSearchAllNodes
			)
			guard let best = results.first else { return }

			// Expand parent nodes if searching all nodes
			if typeAheadSearchAllNodes {
				for parentID in best.parentIDs {
					expandedIDs.insert(parentID)
				}
			}

			selectedID = best.nodeID

			// Scroll to the matched node after a brief delay to allow expansion
			Task { @MainActor in
				try? await Task.sleep(for: .milliseconds(50))
				withAnimation {
					scrollProxy.scrollTo(best.nodeID, anchor: .center)
				}
			}
		}
	}

	/**
	 Handles a navigation request from toolbar search.
	 Expands parent nodes, sets selection, and scrolls to the target node.
	 */
	private func handleNavigationRequest(scrollProxy: ScrollViewProxy) {
		guard let request = searchNavState.navigationRequest,
		      request.targetTab == .periphery else { return }

		// Expand parent nodes to reveal the target
		for parentID in request.parentIDsToExpand {
			expandedIDs.insert(parentID)
		}

		selectedID = request.targetNodeID

		// Clear the request so other views don't also process it
		searchNavState.navigationRequest = nil

		// Scroll to the target after a brief delay for expansion to take effect
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(100))
			withAnimation {
				scrollProxy.scrollTo(request.targetNodeID, anchor: .center)
			}
		}
	}

	private func expandToFileLevel(using nodes: [TreeNode]) {
		var idsToExpand = Set<String>()
		collectFolderIDs(from: nodes, into: &idsToExpand)
		var transaction = Transaction()
		transaction.disablesAnimations = true
		withTransaction(transaction) {
			expandedIDs = idsToExpand
		}
	}

	private func collectFolderIDs(from nodes: [TreeNode], into set: inout Set<String>) {
		for node in nodes {
			switch node {
			case let .folder(folder):
				// Skip auto-expanding PeripherySource folder
				if folder.name == "PeripherySource" {
					continue
				}
				set.insert(folder.id)
				collectFolderIDs(from: folder.children, into: &set)
			case .file:
				break
			}
		}
	}

	private func currentCopyableText(from nodes: [TreeNode]) -> String? {
		guard let selectedID,
		      let node = TreeNodeFinder.findTreeNode(withID: selectedID, in: nodes) else {
			return nil
		}
		return TreeCopyFormatter.formatForCopy(node: node, scanResults: scanResults, filterState: filterState)
	}

	/**
	 Builds the alert message for removal summary.

	 Includes deletion counts, non-deletable warnings, and manual deletion requirements.
	 Shows file count when more than one file was processed.
	 */
	private func buildSummaryMessage(_ summary: RemovalSummary) -> String {
		var message = "\(summary.targetName)\n\n"

		// Show file count if more than one file
		if summary.fileCount > 1 {
			message += "Processed \(summary.fileCount) files\n\n"
		}

		message += "✓ Deleted: \(summary.deletedCount) warning\(summary.deletedCount == 1 ? "" : "s")\n"

		if summary.nonDeletableCount > 0 {
			message += "⚠️ Non-deletable: \(summary.nonDeletableCount) warning\(summary.nonDeletableCount == 1 ? "" : "s") "
			message += "(assign-only property, redundant protocol)\n"
		}

		if summary.failedIgnoreCommentsCount > 0 {
			message += "⚠️ Manual deletion needed: \(summary.failedIgnoreCommentsCount) ignore comment\(summary.failedIgnoreCommentsCount == 1 ? "" : "s")\n"
		}

		if summary.skippedReferencedCount > 0 {
			message += "⏭ Skipped: \(summary.skippedReferencedCount) declaration\(summary.skippedReferencedCount == 1 ? "" : "s") still referenced by other unused code\n"
		}

		return message
	}

	private func filterNode(_ node: TreeNode, with filterState: FilterState) -> TreeNode? {
		switch node {
		case var .folder(folder):
			let filteredChildren = folder.children.compactMap { filterNode($0, with: filterState) }
			guard !filteredChildren.isEmpty else { return nil }
			folder.children = filteredChildren
			return .folder(folder)

		case let .file(file):
			// Check if file is manually hidden via "Ignore All Warnings"
			if hiddenFileIDs.contains(file.id) {
				return nil
			}

			// Use index to get filtered results for this file
			let filteredResults = resultIndex.filteredResults(
				forFile: file.path,
				filterState: filterState,
				hiddenWarningIDs: hiddenWarningIDs
			)
			return filteredResults.isEmpty ? nil : node
		}
	}

	/**
	 Inserts a periphery:ignore:all comment at the top of the file and hides it from the tree.

	 Supports full undo/redo, including restoring empty folders that were removed.
	 */
	private func ignoreAllWarnings(for file: FileNode) {
		// Insert the ignore comment and get original/modified contents
		let result: (original: String, modified: String)
		do {
			result = try PeripheryIgnoreCommentInserter.insertIgnoreAllComment(at: file.path)
		} catch {
			operationError = OperationError(message: "Failed to insert ignore comment: \(error.localizedDescription)")
			return
		}

		// Capture state for undo/redo
		let capturedOriginal = result.original
		let capturedModified = result.modified
		let capturedPath = file.path
		let capturedFileID = file.id
		let wasSelected = selectedID == file.id

		// Invalidate file cache so subsequent reads get the modified content
		SourceFileReader.invalidateCache(for: file.path)

		// Start removal animation
		withAnimation(.easeInOut(duration: 0.3)) {
			removingFileIDs.insert(file.id)
		}

		// Delay for animation duration, then actually hide
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(300))

			// Add file to hidden set (this will trigger re-filtering via @State)
			hiddenFileIDs.insert(file.id)

			// Find folders that became empty and hide them too
			let emptyFolderIDs = findEmptyAncestorIDs(for: file.id, in: rootNodes)
			for folderID in emptyFolderIDs {
				hiddenFileIDs.insert(folderID)
			}

			// Deselect if this file was selected
			if wasSelected {
				selectedID = nil
			}

			// Clean up removing state
			removingFileIDs.remove(file.id)

			// Capture empty folder IDs for undo
			let capturedEmptyFolders = emptyFolderIDs

			// Register undo/redo now that we have emptyFolderIDs
			registerUndoRedo(
				capturedOriginal: capturedOriginal,
				capturedModified: capturedModified,
				capturedPath: capturedPath,
				capturedFileID: capturedFileID,
				wasSelected: wasSelected,
				emptyFolderIDs: capturedEmptyFolders,
				hiddenFileIDs: $hiddenFileIDs,
				removingFileIDs: $removingFileIDs,
				selectedID: $selectedID,
				undoManager: undoManager
			)
		}
	}

	/**
	 Registers undo/redo for the ignore all warnings action.

	 Captures Binding values instead of relying on implicit self capture,
	 since self is a struct and would be captured by value (becoming stale).
	 */
	private func registerUndoRedo(
		capturedOriginal: String,
		capturedModified: String,
		capturedPath: String,
		capturedFileID: String,
		wasSelected: Bool,
		emptyFolderIDs: [String],
		hiddenFileIDs: Binding<Set<String>>,
		removingFileIDs: Binding<Set<String>>,
		selectedID: Binding<String?>,
		undoManager: UndoManager?
	) {
		func performUndo() {
			do {
				try capturedOriginal.write(toFile: capturedPath, atomically: true, encoding: .utf8)
			} catch {
				print("Failed to restore file during undo: \(error)")
				return
			}

			SourceFileReader.invalidateCache(for: capturedPath)

			Task { @MainActor in
				removingFileIDs.wrappedValue.remove(capturedFileID)

				hiddenFileIDs.wrappedValue.remove(capturedFileID)
				for folderID in emptyFolderIDs {
					hiddenFileIDs.wrappedValue.remove(folderID)
				}

				if wasSelected {
					selectedID.wrappedValue = capturedFileID
				}

				undoManager?.registerUndo(withTarget: NSObject()) { _ in
					performRedo()
				}
			}
		}

		func performRedo() {
			do {
				try capturedModified.write(toFile: capturedPath, atomically: true, encoding: .utf8)
			} catch {
				print("Failed to write file during redo: \(error)")
				return
			}

			SourceFileReader.invalidateCache(for: capturedPath)

			Task { @MainActor in
				removingFileIDs.wrappedValue.remove(capturedFileID)

				hiddenFileIDs.wrappedValue.insert(capturedFileID)
				for folderID in emptyFolderIDs {
					hiddenFileIDs.wrappedValue.insert(folderID)
				}

				if wasSelected {
					selectedID.wrappedValue = nil
				}

				undoManager?.registerUndo(withTarget: NSObject()) { _ in
					performUndo()
				}
			}
		}

		undoManager?.registerUndo(withTarget: NSObject()) { _ in
			performUndo()
		}
	}

	/**
	 Finds ancestor folder IDs that will become empty after hiding the specified file.

	 This method must be called AFTER adding the fileID to hiddenFileIDs so it can accurately
	 determine which folders will be empty after filtering.
	 */
	private func findEmptyAncestorIDs(for fileID: String, in nodes: [TreeNode]) -> [String] {
		// First, find the path from root to the file (list of ancestor folder IDs)
		guard let ancestorPath = findAncestorPath(for: fileID, in: nodes) else {
			return []
		}

		var emptyFolderIDs: [String] = []

		// Check each ancestor from bottom to top (child to parent)
		for ancestorID in ancestorPath.reversed() {
			// Find the folder node
			guard let folderNode = TreeNodeFinder.findTreeNode(withID: ancestorID, in: nodes),
			      case let .folder(folder) = folderNode else {
				continue
			}

			// Apply filtering to see if this folder would have any visible children
			let filteredFolder = filterNode(.folder(folder), with: filterState ?? FilterState())

			// If filtering returns nil, the folder is empty
			if filteredFolder == nil {
				emptyFolderIDs.append(ancestorID)
			} else {
				// Stop checking ancestors once we find a non-empty folder
				break
			}
		}

		return emptyFolderIDs
	}

	/**
	 Finds the list of ancestor folder IDs from root to the parent of the given node.
	 */
	private func findAncestorPath(for nodeID: String, in nodes: [TreeNode], currentPath: [String] = []) -> [String]? {
		for node in nodes {
			switch node {
			case let .folder(folder):
				// Check if the target is a direct child of this folder
				if folder.children.contains(where: { $0.id == nodeID }) {
					return currentPath + [folder.id]
				}

				// Recurse into this folder's children
				if let path = findAncestorPath(
					for: nodeID,
					in: folder.children,
					currentPath: currentPath + [folder.id]
				) {
					return path
				}

			case .file:
				continue
			}
		}
		return nil
	}

	/**
	 Generates an appropriate "Copy" menu label based on warning count.

	 Returns "Copy Warning" for single warnings, "Copy Warnings" for multiple.
	 */
	private func copyMenuLabel(for node: TreeNode) -> String {
		let warningCount = countWarnings(in: node)
		return warningCount == 1 ? "Copy Warning" : "Copy Warnings"
	}

	/**
	 Generates an appropriate "Copy File Path" menu label based on file count.

	 Returns "Copy File Path" for single files, "Copy File Paths" for multiple.
	 */
	private func copyPathMenuLabel(for node: TreeNode) -> String {
		let fileCount = countFiles(in: node)
		return fileCount == 1 ? "Copy File Path" : "Copy File Paths"
	}

	/**
	 Counts warnings in a tree node respecting the current filter state.
	 Uses the result index for efficient filtering.
	 */
	private func countWarnings(in node: TreeNode) -> Int {
		switch node {
		case let .file(file):
			resultIndex.filteredResults(
				forFile: file.path,
				filterState: filterState,
				hiddenWarningIDs: hiddenWarningIDs
			).count

		case let .folder(folder):
			folder.children.reduce(0) { $0 + countWarnings(in: $1) }
		}
	}

	/**
	 Counts files in a tree node respecting the current filter state.
	 */
	private func countFiles(in node: TreeNode) -> Int {
		switch node {
		case .file:
			1

		case let .folder(folder):
			folder.children.reduce(0) { $0 + countFiles(in: $1) }
		}
	}

	/**
	 Copies file paths to clipboard.

	 Collects all file paths from the node and copies them to the clipboard, one per line.
	 */
	private func copyFilePathsToClipboard(for node: TreeNode) {
		var paths: [String] = []
		collectFilePaths(from: node, into: &paths)
		let text = paths.joined(separator: "\n")
		TreeCopyFormatter.copyToClipboard(text)
	}

	/**
	 Recursively collects file paths from a tree node.
	 */
	private func collectFilePaths(from node: TreeNode, into paths: inout [String]) {
		switch node {
		case let .file(file):
			paths.append(file.path)

		case let .folder(folder):
			for child in folder.children {
				collectFilePaths(from: child, into: &paths)
			}
		}
	}

	/**
	 Shows the strategy sheet before removing unused code for a file.
	 */
	private func requestRemoveUnusedCode(for file: FileNode) {
		pendingRemovalTarget = .file(file)
		pendingDependencyChains = buildChainsForTarget(.file(file))
		showStrategySheet = true
	}

	/**
	 Shows the strategy sheet before removing unused code for a folder.
	 */
	private func requestRemoveUnusedCodeInFolder(folder: FolderNode) {
		pendingRemovalTarget = .folder(folder)
		pendingDependencyChains = buildChainsForTarget(.folder(folder))
		showStrategySheet = true
	}

	private var pendingRemovalTargetName: String {
		switch pendingRemovalTarget {
		case let .file(file): file.name
		case let .folder(folder): folder.name
		case nil: ""
		}
	}

	/**
	 Builds dependency chains for the given removal target.
	 Gathers the same operations that would be passed to removal,
	 then calls the analyzer to trace caller chains.
	 */
	private func buildChainsForTarget(_ target: RemovalTarget) -> [DependencyChain] {
		let allUnused: Set<Declaration>? = sourceGraph?.unusedDeclarations

		// Collect file paths in scope
		var filePaths: [String] = []
		var scopePath = ""

		switch target {
		case let .file(file):
			filePaths = [file.path]
			scopePath = file.path
		case let .folder(folder):
			var files: [FileNode] = []
			collectFilesWithWarnings(from: .folder(folder), into: &files)
			filePaths = files.map(\.path)
			// Scope path is the folder's common prefix
			if let first = filePaths.first {
				scopePath = filePaths.reduce(first) { result, path in
					String(result.commonPrefix(with: path))
				}
			}
		}

		let filePathSet = Set(filePaths)

		// Gather removable operations for all files in scope
		let operations: [FilteredOperations.Operation] = scanResults.compactMap { scanResult in
			let declaration = scanResult.declaration
			let location = ScanResultHelper.location(from: declaration)
			guard filePathSet.contains(location.file.path.string) else { return nil }

			if let filterState {
				guard filterState.shouldShow(scanResult: scanResult, declaration: declaration) else {
					return nil
				}
			}

			let hasFullRange = location.endLine != nil && location.endColumn != nil
			let isImport = declaration.kind == .module
			guard scanResult.annotation.canRemoveCode(
				hasFullRange: hasFullRange,
				isImport: isImport,
				location: location
			) else {
				return nil
			}

			return (scanResult, declaration, location)
		}

		return UnusedDependencyAnalyzer.buildDependencyChains(
			operations: operations,
			sourceGraph: sourceGraph,
			allUnusedDeclarations: allUnused,
			scopePath: scopePath
		)
	}

	/**
	 Dispatches the removal operation after the user picks a strategy.
	 */
	private func executePendingRemoval(target: RemovalTarget, strategy: RemovalStrategy) {
		pendingRemovalTarget = nil
		pendingDependencyChains = []
		switch target {
		case let .file(file):
			removeAllUnusedCode(for: file, strategy: strategy)
		case let .folder(folder):
			removeAllUnusedCodeInFolder(folder: folder, strategy: strategy)
		}
	}

	/**
	 Removes all unused code from a file.

	 Processes all warnings in the file and removes code where possible,
	 working from bottom to top to preserve line numbers during deletion.
	 Supports full undo/redo.
	 */
	private func removeAllUnusedCode(for file: FileNode, strategy: RemovalStrategy) {
		let allUnused: Set<Declaration>? = sourceGraph?.unusedDeclarations
		let result = file.removeAllUnusedCode(
			scanResults: scanResults,
			filterState: filterState,
			sourceGraph: sourceGraph,
			strategy: strategy,
			allUnusedDeclarations: allUnused
		)

		switch result {
		case let .success(removalResult):
			// Invalidate file cache
			SourceFileReader.invalidateCache(for: file.path)

			// Check if file should be deleted
			var fileWasDeleted = false
			if removalResult.shouldDeleteFile {
				fileWasDeleted = FileDeletionHandler.moveToTrash(filePath: file.path)

				if fileWasDeleted {
					ModificationLogger.log(filePath: file.path, action: "Deleted file")
					// Hide file from tree
					hiddenFileIDs.insert(file.id)
					// Hide empty ancestor folders
					let emptyFolderIDs = findEmptyAncestorIDs(for: file.id, in: rootNodes)
					for folderID in emptyFolderIDs {
						hiddenFileIDs.insert(folderID)
					}

					// Clear selection if this file was selected
					// (inspector will be cleared automatically via onChange observer)
					if selectedID == file.id {
						selectedID = nil
					}
				}
			}

			// Hide all removed warnings with animation
			for warningID in removalResult.removedWarningIDs {
				withAnimation(.easeInOut(duration: 0.3)) {
					hiddenWarningIDs.insert(warningID)
				}
			}

			// Check if file will be filtered out (has no remaining visible warnings)
			let remainingVisibleWarnings = resultIndex.filteredResults(
				forFile: file.path,
				filterState: filterState,
				hiddenWarningIDs: hiddenWarningIDs
			)

			// Clear selection and inspector if file will disappear from tree
			if remainingVisibleWarnings.isEmpty, selectedID == file.id {
				selectedID = nil
			}

			// Register undo/redo
			registerRemoveAllUndo(
				filePath: removalResult.filePath,
				originalContents: removalResult.originalContents,
				modifiedContents: removalResult.modifiedContents,
				removedWarningIDs: removalResult.removedWarningIDs,
				fileWasDeleted: fileWasDeleted,
				fileID: file.id,
				hiddenFileIDs: $hiddenFileIDs,
				hiddenWarningIDs: $hiddenWarningIDs,
				undoManager: undoManager
			)

			// Post notifications for each removed warning
			for warningID in removalResult.removedWarningIDs {
				NotificationCenter.default.post(
					name: Notification.Name("PeripheryWarningCompleted"),
					object: warningID
				)
			}

			// Show deletion summary
			removalSummary = RemovalSummary(
				deletedCount: removalResult.deletionStats.deletedCount,
				nonDeletableCount: removalResult.deletionStats.nonDeletableCount,
				failedIgnoreCommentsCount: removalResult.deletionStats.failedIgnoreCommentsCount,
				skippedReferencedCount: removalResult.deletionStats.skippedReferencedCount,
				fileCount: 1,
				targetName: file.name
			)

		case let .failure(error):
			let nsError = error as NSError
			if nsError.domain == "FileNode", nsError.code == 2 {
				// All warnings were skipped — show informational message
				removalSummary = RemovalSummary(
					deletedCount: 0,
					nonDeletableCount: 0,
					failedIgnoreCommentsCount: 0,
					skippedReferencedCount: 0,
					fileCount: 1,
					targetName: file.name
				)
			} else {
				operationError = OperationError(message: "Failed to remove unused code: \(error.localizedDescription)")
			}
		}
	}

	/**
	 Registers undo/redo for the remove all unused code action.

	 Captures Binding values instead of relying on implicit self capture,
	 since self is a struct and would be captured by value (becoming stale).
	 */
	private func registerRemoveAllUndo(
		filePath: String,
		originalContents: String,
		modifiedContents: String,
		removedWarningIDs: [String],
		fileWasDeleted: Bool,
		fileID: String,
		hiddenFileIDs: Binding<Set<String>>,
		hiddenWarningIDs: Binding<Set<String>>,
		undoManager: UndoManager?
	) {
		@MainActor
		func performUndo() {
			_ = FileDeletionHandler.restoreFile(filePath: filePath, contents: originalContents)

			if fileWasDeleted {
				hiddenFileIDs.wrappedValue.remove(fileID)
			}

			SourceFileReader.invalidateCache(for: filePath)

			Task { @MainActor in
				for warningID in removedWarningIDs {
					hiddenWarningIDs.wrappedValue.remove(warningID)

					NotificationCenter.default.post(
						name: Notification.Name("PeripheryWarningRestored"),
						object: warningID
					)
				}

				undoManager?.registerUndo(withTarget: NSObject()) { _ in
					performRedo()
				}
				undoManager?.setActionName(Self.removeUnusedCodeLabel)
			}
		}

		@MainActor
		func performRedo() {
			if fileWasDeleted {
				_ = FileDeletionHandler.moveToTrash(filePath: filePath)
				hiddenFileIDs.wrappedValue.insert(fileID)
			} else {
				do {
					try modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
				} catch {
					print("Failed to write file during redo: \(error)")
					return
				}
			}

			SourceFileReader.invalidateCache(for: filePath)

			Task { @MainActor in
				for warningID in removedWarningIDs {
					hiddenWarningIDs.wrappedValue.insert(warningID)

					NotificationCenter.default.post(
						name: Notification.Name("PeripheryWarningCompleted"),
						object: warningID
					)
				}

				undoManager?.registerUndo(withTarget: NSObject()) { _ in
					performUndo()
				}
				undoManager?.setActionName(Self.removeUnusedCodeLabel)
			}
		}

		undoManager?.registerUndo(withTarget: NSObject()) { _ in
			performUndo()
		}
		undoManager?.setActionName(Self.removeUnusedCodeLabel)
	}

	/**
	 Ignores all warnings in a folder by inserting ignore directives in all files.

	 Processes each file in the folder (recursively) that has visible warnings based
	 on the current filter state. Supports full undo/redo.
	 */
	private func ignoreAllWarningsInFolder(folder: FolderNode) {
		Task { @MainActor in
			// Collect all files with warnings in this folder
			var filesToIgnore: [FileNode] = []
			collectFilesWithWarnings(from: .folder(folder), into: &filesToIgnore)

			guard !filesToIgnore.isEmpty else {
				print("No files with warnings in folder")
				return
			}

			// Process each file with progress tracking
			var fileModifications: [(path: String, original: String, modified: String, fileID: String)] = []
			var processedFileIDs: [String] = []

			await processFilesWithProgress(filesToIgnore) { file in
				// Insert ignore comment
				let result = try PeripheryIgnoreCommentInserter.insertIgnoreAllComment(at: file.path)

				fileModifications.append((file.path, result.original, result.modified, file.id))
				SourceFileReader.invalidateCache(for: file.path)
				processedFileIDs.append(file.id)
			}

			// Only register undo if not cancelled
			guard !fileOperationProgress.isCancelled else { return }

			// Batch animation for all files at once
			withAnimation(.easeInOut(duration: 0.3)) {
				for fileID in processedFileIDs {
					hiddenFileIDs.insert(fileID)
				}
			}

			// Register undo/redo
			registerIgnoreAllInFolderUndo(
				fileModifications: fileModifications,
				hiddenFileIDs: $hiddenFileIDs,
				undoManager: undoManager
			)
		}
	}

	/**
	 Registers undo/redo for ignoring all warnings in a folder.

	 Captures Binding values instead of relying on implicit self capture,
	 since self is a struct and would be captured by value (becoming stale).
	 */
	private func registerIgnoreAllInFolderUndo(
		fileModifications: [(path: String, original: String, modified: String, fileID: String)],
		hiddenFileIDs: Binding<Set<String>>,
		undoManager: UndoManager?
	) {
		@MainActor
		func performUndo() {
			for modification in fileModifications {
				do {
					try modification.original.write(toFile: modification.path, atomically: true, encoding: .utf8)
				} catch {
					print("Failed to restore file during undo: \(error)")
					continue
				}

				SourceFileReader.invalidateCache(for: modification.path)

				Task { @MainActor in
					hiddenFileIDs.wrappedValue.remove(modification.fileID)
				}
			}

			undoManager?.registerUndo(withTarget: NSObject()) { _ in
				performRedo()
			}
			undoManager?.setActionName("Ignore All Warnings")
		}

		@MainActor
		func performRedo() {
			for modification in fileModifications {
				do {
					try modification.modified.write(toFile: modification.path, atomically: true, encoding: .utf8)
				} catch {
					print("Failed to write file during redo: \(error)")
					continue
				}

				SourceFileReader.invalidateCache(for: modification.path)

				Task { @MainActor in
					hiddenFileIDs.wrappedValue.insert(modification.fileID)
				}
			}

			undoManager?.registerUndo(withTarget: NSObject()) { _ in
				performUndo()
			}
			undoManager?.setActionName("Ignore All Warnings")
		}

		undoManager?.registerUndo(withTarget: NSObject()) { _ in
			performUndo()
		}
		undoManager?.setActionName("Ignore All Warnings")
	}

	/**
	 Removes all unused code in a folder.

	 Processes each file in the folder (recursively) that has removable warnings.
	 Supports full undo/redo.
	 */
	private func removeAllUnusedCodeInFolder(folder: FolderNode, strategy: RemovalStrategy) {
		Task { @MainActor in
			// Collect all files with warnings in this folder
			var filesToProcess: [FileNode] = []
			collectFilesWithWarnings(from: .folder(folder), into: &filesToProcess)

			guard !filesToProcess.isEmpty else {
				print("No files with warnings in folder")
				return
			}

			let allUnused: Set<Declaration>? = sourceGraph?.unusedDeclarations

			// Process each file with progress tracking
			var fileModifications: [(
				path: String,
				original: String,
				modified: String,
				warningIDs: [String],
				wasDeleted: Bool,
				fileID: String
			)] = []
			var allRemovedWarningIDs: [String] = []
			var totalDeleted = 0
			var totalNonDeletable = 0
			var totalFailedIgnores = 0
			var totalSkippedReferenced = 0
			var filesProcessed = 0

			await processFilesWithProgress(filesToProcess) { file in
				// Process file
				let result = file.removeAllUnusedCode(
					scanResults: scanResults,
					filterState: filterState,
					sourceGraph: sourceGraph,
					strategy: strategy,
					allUnusedDeclarations: allUnused
				)

				switch result {
				case let .success(removalResult):
					SourceFileReader.invalidateCache(for: file.path)

					// Check if file should be deleted
					var fileWasDeleted = false
					if removalResult.shouldDeleteFile {
						fileWasDeleted = FileDeletionHandler.moveToTrash(filePath: file.path)

						if fileWasDeleted {
							ModificationLogger.log(filePath: file.path, action: "Deleted file")
							// Hide file from tree
							hiddenFileIDs.insert(file.id)
						}
					}

					fileModifications.append((
						removalResult.filePath,
						removalResult.originalContents,
						removalResult.modifiedContents,
						removalResult.removedWarningIDs,
						fileWasDeleted,
						file.id
					))

					allRemovedWarningIDs.append(contentsOf: removalResult.removedWarningIDs)

					// Accumulate statistics
					totalDeleted += removalResult.deletionStats.deletedCount
					totalNonDeletable += removalResult.deletionStats.nonDeletableCount
					totalFailedIgnores += removalResult.deletionStats.failedIgnoreCommentsCount
					totalSkippedReferenced += removalResult.deletionStats.skippedReferencedCount
					filesProcessed += 1

				case let .failure(error):
					// Only log if it's not the "no removable warnings" case
					let nsError = error as NSError
					if nsError.domain == "FileNode", nsError.code == 2 {
						// This is normal - file has warnings but none are removable
						// (e.g., .assignOnlyProperty, .redundantProtocol, or filtered warnings)
					} else {
						print("Failed to remove unused code from \(file.path): \(error.localizedDescription)")
					}
				}
			}

			// Only register undo if not cancelled
			guard !fileOperationProgress.isCancelled else { return }

			// Batch animation for all warnings at once
			withAnimation(.easeInOut(duration: 0.3)) {
				for warningID in allRemovedWarningIDs {
					hiddenWarningIDs.insert(warningID)
				}
			}

			// Clear selection if the selected file was removed or has no remaining warnings
			if let selectedID {
				// Check if selected file was explicitly deleted/hidden
				if hiddenFileIDs.contains(selectedID) {
					self.selectedID = nil
				} else if let selectedNode = TreeNodeFinder.findTreeNode(withID: selectedID, in: rootNodes),
				          case let .file(selectedFile) = selectedNode {
					// Check if selected file has no remaining visible warnings
					let remainingWarnings = resultIndex.filteredResults(
						forFile: selectedFile.path,
						filterState: filterState,
						hiddenWarningIDs: hiddenWarningIDs
					)
					if remainingWarnings.isEmpty {
						self.selectedID = nil
					}
				}
			}

			// Post notifications for all warnings
			for warningID in allRemovedWarningIDs {
				NotificationCenter.default.post(
					name: Notification.Name("PeripheryWarningCompleted"),
					object: warningID
				)
			}

			// Register undo/redo
			if !fileModifications.isEmpty {
				registerRemoveAllInFolderUndo(
					fileModifications: fileModifications,
					hiddenFileIDs: $hiddenFileIDs,
					hiddenWarningIDs: $hiddenWarningIDs,
					undoManager: undoManager
				)
			}

			// Show deletion summary if any files were processed
			if filesProcessed > 0 || totalSkippedReferenced > 0 {
				removalSummary = RemovalSummary(
					deletedCount: totalDeleted,
					nonDeletableCount: totalNonDeletable,
					failedIgnoreCommentsCount: totalFailedIgnores,
					skippedReferencedCount: totalSkippedReferenced,
					fileCount: filesProcessed,
					targetName: folder.name
				)
			}
		}
	}

	/**
	 Registers undo/redo for removing all unused code in a folder.

	 Captures Binding values instead of relying on implicit self capture,
	 since self is a struct and would be captured by value (becoming stale).
	 */
	private func registerRemoveAllInFolderUndo(
		fileModifications: [(
			path: String,
			original: String,
			modified: String,
			warningIDs: [String],
			wasDeleted: Bool,
			fileID: String
		)],
		hiddenFileIDs: Binding<Set<String>>,
		hiddenWarningIDs: Binding<Set<String>>,
		undoManager: UndoManager?
	) {
		@MainActor
		func performUndo() {
			for modification in fileModifications {
				_ = FileDeletionHandler.restoreFile(filePath: modification.path, contents: modification.original)

				if modification.wasDeleted {
					hiddenFileIDs.wrappedValue.remove(modification.fileID)
				}

				SourceFileReader.invalidateCache(for: modification.path)

				Task { @MainActor in
					for warningID in modification.warningIDs {
						hiddenWarningIDs.wrappedValue.remove(warningID)

						NotificationCenter.default.post(
							name: Notification.Name("PeripheryWarningRestored"),
							object: warningID
						)
					}
				}
			}

			undoManager?.registerUndo(withTarget: NSObject()) { _ in
				performRedo()
			}
			undoManager?.setActionName(Self.removeUnusedCodeLabel)
		}

		@MainActor
		func performRedo() {
			for modification in fileModifications {
				if modification.wasDeleted {
					_ = FileDeletionHandler.moveToTrash(filePath: modification.path)
					hiddenFileIDs.wrappedValue.insert(modification.fileID)
				} else {
					do {
						try modification.modified.write(toFile: modification.path, atomically: true, encoding: .utf8)
					} catch {
						print("Failed to write file during redo: \(error)")
						continue
					}
				}

				SourceFileReader.invalidateCache(for: modification.path)

				Task { @MainActor in
					for warningID in modification.warningIDs {
						hiddenWarningIDs.wrappedValue.insert(warningID)

						NotificationCenter.default.post(
							name: Notification.Name("PeripheryWarningCompleted"),
							object: warningID
						)
					}
				}
			}

			undoManager?.registerUndo(withTarget: NSObject()) { _ in
				performUndo()
			}
			undoManager?.setActionName(Self.removeUnusedCodeLabel)
		}

		undoManager?.registerUndo(withTarget: NSObject()) { _ in
			performUndo()
		}
		undoManager?.setActionName(Self.removeUnusedCodeLabel)
	}

	/**
	 Processes multiple files with progress tracking and cancellation support.
	 */
	private func processFilesWithProgress(
		_ files: [FileNode],
		operation: @escaping (FileNode) async throws -> Void
	) async {
		fileOperationProgress.totalCount = files.count
		fileOperationProgress.processedCount = 0
		fileOperationProgress.isCancelled = false
		fileOperationProgress.isProcessing = true

		// Only show progress sheet if operation takes longer than threshold
		let showProgressTask = Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(300))
			if !fileOperationProgress.isCancelled, fileOperationProgress.isProcessing {
				showProgressSheet = true
			}
		}

		defer {
			showProgressTask.cancel()
			showProgressSheet = false
			fileOperationProgress.reset()
		}

		for (index, file) in files.enumerated() {
			// Check cancellation at file boundaries
			guard !fileOperationProgress.isCancelled else {
				break
			}

			fileOperationProgress.currentFile = file.path
			fileOperationProgress.processedCount = index

			// Yield to UI updates
			await Task.yield()

			do {
				try await operation(file)
			} catch {
				print("Error processing \(file.path): \(error)")
				// Continue processing remaining files
			}
		}

		fileOperationProgress.processedCount = files.count
	}

	/**
	 Collects all file nodes that have warnings from a tree node.
	 Uses the result index for efficient filtering.
	 */
	private func collectFilesWithWarnings(from node: TreeNode, into files: inout [FileNode]) {
		switch node {
		case let .file(file):
			// Check if file has any visible warnings using the index
			let filteredResults = resultIndex.filteredResults(
				forFile: file.path,
				filterState: filterState,
				hiddenWarningIDs: hiddenWarningIDs
			)

			if !filteredResults.isEmpty {
				files.append(file)
			}

		case let .folder(folder):
			for child in folder.children {
				collectFilesWithWarnings(from: child, into: &files)
			}
		}
	}
}

private struct TreeNodeView: View {
	let node: TreeNode
	let filterState: FilterState?
	let scanResults: [ScanResult]
	@Binding var expandedIDs: Set<String>
	@Binding var selectedID: String?
	@Binding var removingFileIDs: Set<String>
	let hiddenWarningIDs: Set<String>
	var indentLevel: Int = 0
	let resultIndex: ScanResultIndex
	let onIgnoreAllWarnings: (FileNode) -> Void
	let onRemoveAllUnusedCode: (FileNode) -> Void
	let onIgnoreAllWarningsInFolder: (FolderNode) -> Void
	let onRemoveAllUnusedCodeInFolder: (FolderNode) -> Void
	let copyMenuLabel: (TreeNode) -> String
	let copyPathMenuLabel: (TreeNode) -> String
	let copyFilePathsToClipboard: (TreeNode) -> Void

	var body: some View {
		switch node {
		case let .folder(folder):
			DisclosureGroup(
				isExpanded: expansionBinding(for: folder.id, in: $expandedIDs)
			) {
				ForEach(folder.children, id: \.id) { child in
					TreeNodeView(
						node: child,
						filterState: filterState,
						scanResults: scanResults,
						expandedIDs: $expandedIDs,
						selectedID: $selectedID,
						removingFileIDs: $removingFileIDs,
						hiddenWarningIDs: hiddenWarningIDs,
						indentLevel: indentLevel + 1,
						resultIndex: resultIndex,
						onIgnoreAllWarnings: onIgnoreAllWarnings,
						onRemoveAllUnusedCode: onRemoveAllUnusedCode,
						onIgnoreAllWarningsInFolder: onIgnoreAllWarningsInFolder,
						onRemoveAllUnusedCodeInFolder: onRemoveAllUnusedCodeInFolder,
						copyMenuLabel: copyMenuLabel,
						copyPathMenuLabel: copyPathMenuLabel,
						copyFilePathsToClipboard: copyFilePathsToClipboard
					)
				}
			} label: {
				Button {
					selectedID = folder.id
				} label: {
					HStack(spacing: 0) {
						ChevronOrPlaceholder(
							hasChildren: !folder.children.isEmpty,
							expandedIDs: $expandedIDs,
							id: folder.id,
							toggleWithDescendants: { toggleWithDescendants(for: .folder(folder)) }
						)

						FolderRowView(folder: folder)
					}
				}
				.buttonStyle(.plain)
				.treeLabelPadding(indentLevel: indentLevel)
				.frame(maxWidth: .infinity, alignment: .leading)
				.contentShape(.rect)
				.background(selectedID == folder.id ? Color.accentColor.opacity(0.2) : Color.clear)
				.simultaneousGesture(
					TapGesture(count: 2)
						.onEnded {
							openFolderInFinder(path: folder.path)
						}
				)
				.contextMenu {
					Button(copyMenuLabel(.folder(folder))) {
						let text = TreeCopyFormatter.formatForCopy(
							node: .folder(folder),
							scanResults: scanResults,
							filterState: filterState
						)
						TreeCopyFormatter.copyToClipboard(text)
					}
					.keyboardShortcut("c", modifiers: .command)

					Button(copyPathMenuLabel(.folder(folder))) {
						copyFilePathsToClipboard(.folder(folder))
					}

					Divider()

					Button("Open in Finder") {
						openFolderInFinder(path: folder.path)
					}

					let fileURL = URL(fileURLWithPath: folder.path)
					Button("Reveal in Finder") {
						NSWorkspace.shared.activateFileViewerSelecting([fileURL])
					}

					Divider()

					Button(PeripheryTreeView.removeUnusedCodeLabel) {
						onRemoveAllUnusedCodeInFolder(folder)
					}

					Button("Ignore All Warnings") {
						onIgnoreAllWarningsInFolder(folder)
					}
				}
			}
			.disclosureGroupStyle(TreeDisclosureStyle())

		case let .file(file):
			Button {
				selectedID = file.id
			} label: {
				HStack(spacing: 0) {
					ChevronOrPlaceholder(
						hasChildren: false,
						expandedIDs: $expandedIDs,
						id: file.id,
						toggleWithDescendants: {}
					)

					FileRowView(
						file: file,
						filterState: filterState,
						scanResults: scanResults,
						removingFileIDs: removingFileIDs,
						hiddenWarningIDs: hiddenWarningIDs,
						resultIndex: resultIndex
					)
				}
			}
			.buttonStyle(.plain)
			.treeLabelPadding(indentLevel: indentLevel)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(selectedID == file.id ? Color.accentColor.opacity(0.2) : Color.clear)
			.contentShape(.rect)
			.simultaneousGesture(
				TapGesture(count: 2)
					.onEnded {
						openFileInEditor(path: file.path)
					}
			)
			.contextMenu {
				Button(copyMenuLabel(.file(file))) {
					let text = TreeCopyFormatter.formatForCopy(
						node: .file(file),
						scanResults: scanResults,
						filterState: filterState
					)
					TreeCopyFormatter.copyToClipboard(text)
				}
				.keyboardShortcut("c", modifiers: .command)

				Button(copyPathMenuLabel(.file(file))) {
					copyFilePathsToClipboard(.file(file))
				}

				Divider()

				Button("Open in Xcode") {
					openFileInEditor(path: file.path)
				}

				Divider()

				Button(PeripheryTreeView.removeUnusedCodeLabel) {
					onRemoveAllUnusedCode(file)
				}

				Button("Ignore All Warnings") {
					onIgnoreAllWarnings(file)
				}
			}
		}
	}

	func toggleWithDescendants(for node: TreeNode) {
		expandedIDs.toggleExpansion(
			id: node.id,
			withDescendants: true,
			collectDescendants: { node.collectDescendantIDs() }
		)
	}
}
