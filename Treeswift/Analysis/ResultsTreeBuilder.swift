//
//  ResultsTreeBuilder.swift
//  Treeswift
//
//  Builds hierarchical tree structure from ScanResults
//

import Foundation
import AppKit
import PeripheryKit
import SourceGraph
import SystemPackage

struct ResultsTreeBuilder {

	nonisolated static func buildTree(from results: [ScanResult], projectRoot: String) -> [TreeNode] {
		// Group results by file location
		var fileGroups: [String: [(result: ScanResult, declaration: Declaration, location: Location)]] = [:]

		for result in results {
			let declaration = result.declaration
			let location = ScanResultHelper.location(from: declaration)
			let filePath = location.file.path.string
			fileGroups[filePath, default: []].append((result, declaration, location))
		}

		// Build file nodes with badges (no warning children)
		var fileNodes: [(path: String, node: FileNode)] = []

		for (filePath, _) in fileGroups {

			let fileName = URL(fileURLWithPath: filePath).lastPathComponent
			let fileNode = FileNode(
				id: filePath,
				name: fileName,
				path: filePath,
			)

			fileNodes.append((path: filePath, node: fileNode))
		}

		// Build folder hierarchy
		return buildFolderHierarchy(fileNodes: fileNodes, projectRoot: projectRoot)
	}
	nonisolated private static func buildFolderHierarchy(
		fileNodes: [(path: String, node: FileNode)],
		projectRoot: String
	) -> [TreeNode] {
		// Dictionary to hold all folders: path -> FolderNode
		var folders: [String: FolderNode] = [:]

		// Create all necessary folders
		for (filePath, _) in fileNodes {
			let folderPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
			createFolderPathIfNeeded(folderPath, in: &folders, projectRoot: projectRoot)
		}

		// Add files to their parent folders
		for (filePath, fileNode) in fileNodes {
			let folderPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path

			if folderPath == projectRoot || !folderPath.hasPrefix(projectRoot) {
				// Will be added to root level later
				continue
			}

			if var folder = folders[folderPath] {
				folder.children.append(.file(fileNode))
				folders[folderPath] = folder
			}
		}

		// Build tree from bottom up
		let sortedPaths = folders.keys.sorted { $0.count > $1.count }

		for path in sortedPaths {
			guard var folder = folders[path] else { continue }

			// Sort children within this folder (folders before files, then alphabetically)
			folder.children.sort { lhs, rhs in
				switch (lhs, rhs) {
				case (.folder(let a), .folder(let b)):
					return a.name < b.name
				case (.file(let a), .file(let b)):
					return a.name < b.name
				case (.folder, .file):
					return true
				case (.file, .folder):
					return false
				}
			}
			folders[path] = folder

			let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path

			if parentPath == projectRoot || !parentPath.hasPrefix(projectRoot) {
				// This is a top-level folder, will be added to root
				continue
			}

			if var parentFolder = folders[parentPath] {
				parentFolder.children.append(.folder(folder))
				folders[parentPath] = parentFolder
			}
		}

		// Collect root-level nodes
		var rootNodes: [TreeNode] = []

		// Add top-level folders
		for (path, folder) in folders {
			let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
			if parentPath == projectRoot || !parentPath.hasPrefix(projectRoot) {
				rootNodes.append(.folder(folder))
			}
		}

		// Add root-level files
		for (filePath, fileNode) in fileNodes {
			let folderPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
			if folderPath == projectRoot || !folderPath.hasPrefix(projectRoot) {
				rootNodes.append(.file(fileNode))
			}
		}

		return rootNodes.sorted { lhs, rhs in
			switch (lhs, rhs) {
			case (.folder(let a), .folder(let b)):
				return a.name < b.name
			case (.file(let a), .file(let b)):
				return a.name < b.name
			case (.folder, .file):
				return true
			case (.file, .folder):
				return false
			}
		}
	}

	nonisolated private static func createFolderPathIfNeeded(
		_ path: String,
		in folders: inout [String: FolderNode],
		projectRoot: String
	) {
		if path == projectRoot || !path.hasPrefix(projectRoot) {
			return
		}

		if folders[path] != nil {
			return
		}

		let folderName = URL(fileURLWithPath: path).lastPathComponent
		folders[path] = FolderNode(
			id: path,
			name: folderName,
			path: path,
			children: []
		)

		// Recursively create parent folders
		let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
		createFolderPathIfNeeded(parentPath, in: &folders, projectRoot: projectRoot)
	}
}

