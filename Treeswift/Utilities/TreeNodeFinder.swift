//
//  TreeNodeFinder.swift
//  Treeswift
//
//  Helper functions to find tree nodes by ID
//

import Foundation

enum TreeNodeFinder {
	// Find TreeNode by ID in Periphery results tree
	static func findTreeNode(withID id: String, in nodes: [TreeNode]) -> TreeNode? {
		for node in nodes {
			if node.id == id {
				return node
			}
			switch node {
			case let .folder(folder):
				if let found = findTreeNode(withID: id, in: folder.children) {
					return found
				}
			case .file:
				break
			}
		}
		return nil
	}

	// Find FileBrowserNode by ID in files tree
	// Find CategoriesNode by ID in categories tree
	static func findCategoriesNode(withID id: String, in nodes: [CategoriesNode]) -> CategoriesNode? {
		for node in nodes {
			if node.id == id {
				return node
			}
			switch node {
			case let .section(section):
				if let found = findCategoriesNode(withID: id, in: section.children) {
					return found
				}
			case let .declaration(decl):
				if let found = findCategoriesNode(withID: id, in: decl.children) {
					return found
				}
			case let .syntheticRoot(root):
				if let found = findCategoriesNode(withID: id, in: root.children) {
					return found
				}
			}
		}
		return nil
	}
}
