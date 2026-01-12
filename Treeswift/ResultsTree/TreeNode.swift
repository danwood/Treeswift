//
//  TreeNode.swift
//  Treeswift
//
//  Core tree node types for hierarchical results tree
//

import Foundation

enum TreeNode: Identifiable, Hashable, Sendable {
	case folder(FolderNode)
	case file(FileNode)

	var id: String {
		switch self {
		case .folder(let node): node.id
		case .file(let node): node.id
		}
	}

	// Collects all descendant IDs recursively
	func collectDescendantIDs() -> Set<String> {
		var result = Set<String>()
		collectDescendantIDs(into: &result)
		return result
	}

	private func collectDescendantIDs(into set: inout Set<String>) {
		switch self {
		case .folder(let folder):
			set.insert(folder.id)
			for child in folder.children {
				child.collectDescendantIDs(into: &set)
			}
		case .file(let file):
			set.insert(file.id)
		}
	}
}

struct FolderNode: Identifiable, Hashable, Sendable {
	let id: String
	let name: String
	let path: String
	var children: [TreeNode]
}

struct FileNode: Identifiable, Hashable, Sendable {
	let id: String
	let name: String
	let path: String
}

extension TreeNode: NavigableTreeNode {
	var navigationID: String { id }

	var isExpandable: Bool {
		switch self {
		case .folder: true
		case .file: false
		}
	}

	var childNodes: [any NavigableTreeNode] {
		switch self {
		case .folder(let folder): folder.children
		case .file: []
		}
	}
}
