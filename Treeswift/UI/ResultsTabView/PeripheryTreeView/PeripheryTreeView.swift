//
//  PeripheryTreeView.swift
//  Treeswift
//
//  Hierarchical tree view for scan results
//

import SwiftUI
import AppKit
import PeripheryKit
import SourceGraph
import SystemPackage

struct PeripheryTreeView: View {
	let rootNodes: [TreeNode]
	let scanResults: [ScanResult]
	let filterState: FilterState?
	@Binding var selectedID: String?
	@State private var expandedIDs: Set<String> = []
	@State private var hasAppearedOnce: Bool = false
	@State private var claimFocusTrigger: Bool = false
	@State private var filteredNodesCache: [TreeNode] = []
	@State private var hiddenFileIDs: Set<String> = []
	@State private var removingFileIDs: Set<String> = []
	@State private var hiddenWarningIDs: Set<String> = []
	@Environment(\.undoManager) private var undoManager

	var body: some View {
		// Force dependency on filterChangeCounter by accessing it in body

		return VStack(alignment: .leading, spacing: 0) {
			ForEach(filteredNodesCache, id: \.id) { node in
				TreeNodeView(
					node: node,
					filterState: filterState,
					scanResults: scanResults,
					expandedIDs: $expandedIDs,
					selectedID: $selectedID,
					removingFileIDs: $removingFileIDs,
					hiddenWarningIDs: hiddenWarningIDs,
					onIgnoreAllWarnings: ignoreAllWarnings
				)
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.focusableTreeNavigation(
			selectedID: $selectedID,
			visibleItems: TreeKeyboardNavigation.buildVisibleItemList(nodes: filteredNodesCache, expandedIDs: expandedIDs),
			claimFocusTrigger: $claimFocusTrigger
		)
		.focusedValue(\.copyableText, currentCopyableText(from: filteredNodesCache))
		.focusedValue(\.copyMenuTitle, "Copy Periphery Warnings")
		.onCopyCommand {
			guard let text = currentCopyableText(from: filteredNodesCache) else { return [] }
			return [NSItemProvider(object: text as NSString)]
		}
		.onAppear {
			recomputeFilteredNodes()
			// Only expand on first appearance to avoid re-expanding when switching tabs
			if expandedIDs.isEmpty {
				expandToFileLevel(using: rootNodes)
			}

			if !hasAppearedOnce {
				hasAppearedOnce = true
				Task { @MainActor in
					try? await Task.sleep(for: .milliseconds(50))
					claimFocusTrigger.toggle()
				}
			}
		}
		.onChange(of: rootNodes) {
			recomputeFilteredNodes()
		}
		.onChange(of: filterState?.filterChangeCounter) { oldValue, newValue in
			recomputeFilteredNodes()
		}
		.onChange(of: scanResults) {
			recomputeFilteredNodes()
		}
		.onChange(of: hiddenFileIDs) {
			recomputeFilteredNodes()
		}
		.onChange(of: hiddenWarningIDs) {
			recomputeFilteredNodes()
		}
		.onReceive(NotificationCenter.default.publisher(for: Notification.Name("PeripheryWarningCompleted"))) { notification in
			if let warningID = notification.object as? String {
				hiddenWarningIDs.insert(warningID)
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: Notification.Name("PeripheryWarningRestored"))) { notification in
			if let warningID = notification.object as? String {
				hiddenWarningIDs.remove(warningID)
			}
		}
	}

	private func recomputeFilteredNodes() {
		let newFiltered: [TreeNode]
		if let filterState = filterState {
			newFiltered = rootNodes.compactMap { filterNode($0, with: filterState) }
		} else {
			newFiltered = rootNodes
		}
		// Always update - SwiftUI will handle diff efficiently
		filteredNodesCache = newFiltered
	}

	private func expandToFileLevel(using nodes: [TreeNode]) {
		var idsToExpand = Set<String>()
		collectFolderIDs(from: nodes, into: &idsToExpand)
		// Defer state update to next run loop to avoid reentrant layout
		Task { @MainActor in
			expandedIDs = idsToExpand
		}
	}

	private func collectFolderIDs(from nodes: [TreeNode], into set: inout Set<String>) {
		for node in nodes {
			switch node {
			case .folder(let folder):
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
		guard let selectedID = selectedID,
			  let node = TreeNodeFinder.findTreeNode(withID: selectedID, in: nodes) else {
			return nil
		}
		return TreeCopyFormatter.formatForCopy(node: node, scanResults: scanResults, filterState: filterState)
	}

	private func filterNode(_ node: TreeNode, with filterState: FilterState) -> TreeNode? {
		switch node {
		case .folder(var folder):
			let filteredChildren = folder.children.compactMap { filterNode($0, with: filterState) }
			guard !filteredChildren.isEmpty else { return nil }
			folder.children = filteredChildren
			return .folder(folder)

		case .file(let file):
			// Check if file is manually hidden via "Ignore All Warnings"
			if hiddenFileIDs.contains(file.id) {
				return nil
			}

			// Check if ANY warning in scanResults for this file matches the filter AND is not hidden
			let hasMatchingWarnings = scanResults.contains { result in
				let declaration = result.declaration
				let location = ScanResultHelper.location(from: declaration)

				// Check if warning is for this file and passes filter
				guard location.file.path.string == file.path else { return false }
				guard filterState.shouldShow(result: result, declaration: declaration) else { return false }

				// Check if warning is not individually hidden
				let usr = declaration.usrs.first ?? ""
				let warningID = "\(location.file.path.string):\(usr)"
				return !hiddenWarningIDs.contains(warningID)
			}
			return hasMatchingWarnings ? node : nil
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
			print("Failed to insert ignore comment: \(error)")
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
		_ = withAnimation(.easeInOut(duration: 0.3)) {
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
				emptyFolderIDs: capturedEmptyFolders
			)
		}
	}

	/**
	Registers undo/redo for the ignore all warnings action.
	*/
	private func registerUndoRedo(
		capturedOriginal: String,
		capturedModified: String,
		capturedPath: String,
		capturedFileID: String,
		wasSelected: Bool,
		emptyFolderIDs: [String]
	) {

		// Register undo/redo using nested closure pattern
		func performUndo() {
			// Restore original file contents
			do {
				try capturedOriginal.write(toFile: capturedPath, atomically: true, encoding: .utf8)
			} catch {
				print("Failed to restore file during undo: \(error)")
				return
			}

			// Invalidate cache
			SourceFileReader.invalidateCache(for: capturedPath)

			// Wrap @State mutations in MainActor
			Task { @MainActor in
				// Clear any animation state
				removingFileIDs.remove(capturedFileID)

				// Remove file and folders from hidden set
				hiddenFileIDs.remove(capturedFileID)
				for folderID in emptyFolderIDs {
					hiddenFileIDs.remove(folderID)
				}

				// Restore selection if it was selected
				if wasSelected {
					selectedID = capturedFileID
				}

				// Register redo AFTER state mutations complete
				undoManager?.registerUndo(withTarget: NSObject()) { _ in
					performRedo()
				}
			}
		}

		func performRedo() {
			// Write modified contents
			do {
				try capturedModified.write(toFile: capturedPath, atomically: true, encoding: .utf8)
			} catch {
				print("Failed to write file during redo: \(error)")
				return
			}

			// Invalidate cache
			SourceFileReader.invalidateCache(for: capturedPath)

			// Wrap @State mutations in MainActor
			Task { @MainActor in
				// Skip animation on redo - instant hide
				removingFileIDs.remove(capturedFileID)

				// Re-hide file and folders
				hiddenFileIDs.insert(capturedFileID)
				for folderID in emptyFolderIDs {
					hiddenFileIDs.insert(folderID)
				}

				// Clear selection if it was selected
				if wasSelected {
					selectedID = nil
				}

				// Register undo AFTER state mutations complete
				undoManager?.registerUndo(withTarget: NSObject()) { _ in
					performUndo()
				}
			}
		}

		// Register initial undo
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
				  case .folder(let folder) = folderNode else {
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
			case .folder(let folder):
				// Check if the target is a direct child of this folder
				if folder.children.contains(where: { $0.id == nodeID }) {
					return currentPath + [folder.id]
				}

				// Recurse into this folder's children
				if let path = findAncestorPath(for: nodeID, in: folder.children, currentPath: currentPath + [folder.id]) {
					return path
				}

			case .file:
				continue
			}
		}
		return nil
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
	let onIgnoreAllWarnings: (FileNode) -> Void

	var body: some View {
		switch node {
		case .folder(let folder):
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
						onIgnoreAllWarnings: onIgnoreAllWarnings
					)
				}
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
				.treeLabelPadding(indentLevel: indentLevel)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(selectedID == folder.id ? Color.accentColor.opacity(0.2) : Color.clear)
				.onTapGesture {
					selectedID = folder.id
				}
				.simultaneousGesture(
					TapGesture(count: 2)
						.onEnded {
							openFolderInFinder(path: folder.path)
						}
				)
				.contextMenu {
					Button("Copy") {
						let text = TreeCopyFormatter.formatForCopy(node: .folder(folder), scanResults: scanResults, filterState: filterState)
						TreeCopyFormatter.copyToClipboard(text)
					}
					.keyboardShortcut("c", modifiers: .command)

					Divider()

					Button("Open in Finder") {
						openFolderInFinder(path: folder.path)
					}
				}
			}
			.disclosureGroupStyle(TreeDisclosureStyle())

		case .file(let file):
			HStack(spacing: 0) {
				ChevronOrPlaceholder(
					hasChildren: false,
					expandedIDs: $expandedIDs,
					id: file.id,
					toggleWithDescendants: { }
				)

				FileRowView(file: file, filterState: filterState, scanResults: scanResults, removingFileIDs: removingFileIDs, hiddenWarningIDs: hiddenWarningIDs)
			}
			.treeLabelPadding(indentLevel: indentLevel)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(selectedID == file.id ? Color.accentColor.opacity(0.2) : Color.clear)
			.contentShape(.rect)

			.onTapGesture {
				selectedID = file.id
			}
			.simultaneousGesture(
				TapGesture(count: 2)
					.onEnded {
						openFileInEditor(path: file.path)
					}
			)
			.contextMenu {
				Button("Copy") {
					let text = TreeCopyFormatter.formatForCopy(node: .file(file), scanResults: scanResults, filterState: filterState)
					TreeCopyFormatter.copyToClipboard(text)
				}
				.keyboardShortcut("c", modifiers: .command)

				Divider()

				Button("Open in Xcode") {
					openFileInEditor(path: file.path)
				}

				Divider()

				Button("Ignore All Warnings") {
					onIgnoreAllWarnings(file)
				}
			}
		}
	}

	func toggleWithDescendants(for node: TreeNode) {
		withAnimation(.easeInOut(duration: 0.2)) {
			expandedIDs.toggleExpansion(
				id: node.id,
				withDescendants: true,
				collectDescendants: { node.collectDescendantIDs() }
			)
		}
	}
}

