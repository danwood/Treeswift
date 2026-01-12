//
//  TreeKeyboardNavigation.swift
//  Treeswift
//
//  Keyboard navigation utilities for tree views
//

import SwiftUI

/// Protocol for tree nodes that support keyboard navigation
protocol NavigableTreeNode {
	var navigationID: String { get }
	var isExpandable: Bool { get }
	var childNodes: [any NavigableTreeNode] { get }
}

/// Builds a flat list of visible node IDs for keyboard navigation
enum TreeKeyboardNavigation {

	/// Returns ordered list of visible node IDs based on expansion state
	static func buildVisibleItemList<T: NavigableTreeNode>(
		nodes: [T],
		expandedIDs: Set<String>,
		showFolderPrivateFiles: Bool = true,
		showAllFolders: Bool = true,
		isFolderPrivateCheck: ((T) -> Bool)? = nil
	) -> [String] {
		var visibleIDs: [String] = []
		collectVisibleIDs(
			from: nodes,
			expandedIDs: expandedIDs,
			into: &visibleIDs,
			showFolderPrivateFiles: showFolderPrivateFiles,
			showAllFolders: showAllFolders,
			isFolderPrivateCheck: isFolderPrivateCheck
		)
		return visibleIDs
	}

	private static func collectVisibleIDs<T: NavigableTreeNode>(
		from nodes: [T],
		expandedIDs: Set<String>,
		into list: inout [String],
		showFolderPrivateFiles: Bool,
		showAllFolders: Bool,
		isFolderPrivateCheck: ((T) -> Bool)?
	) {
		for node in nodes {
			// Check folder filtering (only applies to directories)
			if node.isExpandable, !showAllFolders {
				// Skip folders without Swift files
				if case let browserNode as FileBrowserNode = node,
				   case .directory(let dir) = browserNode,
				   !dir.containsSwiftFiles {
					continue
				}
			}

			// Check if this node should be shown (for folder-private filtering)
			if let check = isFolderPrivateCheck, !showFolderPrivateFiles, check(node) {
				continue
			}

			list.append(node.navigationID)

			// If this node is expandable and expanded, recurse into children
			if node.isExpandable && expandedIDs.contains(node.navigationID) {
				collectVisibleIDs(
					from: node.childNodes as! [T],
					expandedIDs: expandedIDs,
					into: &list,
					showFolderPrivateFiles: showFolderPrivateFiles,
					showAllFolders: showAllFolders,
					isFolderPrivateCheck: isFolderPrivateCheck
				)
			}
		}
	}

	/// Moves selection up in the visible item list
	static func moveSelectionUp(
		currentSelection: String?,
		visibleItems: [String]
	) -> String? {
		guard !visibleItems.isEmpty else { return nil }

		guard let current = currentSelection,
			  let currentIndex = visibleItems.firstIndex(of: current) else {
			// No selection or invalid selection - select last item
			return visibleItems.last
		}

		if currentIndex > 0 {
			return visibleItems[currentIndex - 1]
		}
		return current // Already at top
	}

	/// Moves selection down in the visible item list
	static func moveSelectionDown(
		currentSelection: String?,
		visibleItems: [String]
	) -> String? {
		guard !visibleItems.isEmpty else { return nil }

		guard let current = currentSelection,
			  let currentIndex = visibleItems.firstIndex(of: current) else {
			// No selection or invalid selection - select first item
			return visibleItems.first
		}

		if currentIndex < visibleItems.count - 1 {
			return visibleItems[currentIndex + 1]
		}
		return current // Already at bottom
	}
}

extension View {
	func focusableTreeNavigation(
		selectedID: Binding<String?>,
		visibleItems: [String],
		claimFocusTrigger: Binding<Bool>
	) -> some View {
		background(FocusClaimingView(
			selectedID: selectedID,
			visibleItems: visibleItems,
			claimFocusTrigger: claimFocusTrigger
		))
	}
}
