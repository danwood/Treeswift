//
//  TreeNodeFilter.swift
//  Treeswift
//
//  Pure, nonisolated tree-filtering logic safe to run off the main actor.
//

import Foundation
import PeripheryKit
import SourceGraph

/**
 Filters a single TreeNode against the given snapshot state.
 Returns nil if the node (and all its descendants) should be hidden.

 This is a free function so it can be called from a detached Task without
 capturing any MainActor-isolated state.
 */
nonisolated func filterTreeNode(
	_ node: TreeNode,
	filterSnapshot: FilterSnapshot,
	hiddenFileIDs: Set<String>,
	hiddenWarningIDs: Set<String>,
	indexSnapshot: [String: [ScanResult]],
	scanResultsEmpty: Bool
) -> TreeNode? {
	switch node {
	case var .folder(folder):
		let filteredChildren = folder.children.compactMap {
			filterTreeNode(
				$0,
				filterSnapshot: filterSnapshot,
				hiddenFileIDs: hiddenFileIDs,
				hiddenWarningIDs: hiddenWarningIDs,
				indexSnapshot: indexSnapshot,
				scanResultsEmpty: scanResultsEmpty
			)
		}
		guard !filteredChildren.isEmpty else { return nil }
		folder.children = filteredChildren
		return .folder(folder)

	case let .file(file):
		if hiddenFileIDs.contains(file.id) { return nil }
		guard !scanResultsEmpty else { return node }

		let fileResults = indexSnapshot[file.path] ?? []
		let hasVisible = fileResults.contains { result in
			let usr = result.declaration.usrs.first ?? ""
			let warningID = "\(file.path):\(usr)"
			guard !hiddenWarningIDs.contains(warningID) else { return false }
			return filterSnapshot.shouldShow(scanResult: result, declaration: result.declaration)
		}
		return hasVisible ? node : nil
	}
}
