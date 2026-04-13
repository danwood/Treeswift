//
//  ScanResultCodable.swift
//  Treeswift
//
//  Codable response types for automation API results endpoints.
//  These are parallel types to the UI models — separate to avoid modifying model types.
//

import Foundation
import PeripheryKit

// MARK: - Periphery Tree (TreeNode wrappers)

nonisolated struct TreeNodeResponse: Codable, Sendable {
	let id: String
	let type: String // "folder" or "file"
	let name: String
	let path: String
	let children: [TreeNodeResponse]?
}

extension TreeNodeResponse {
	init(from node: TreeNode) {
		switch node {
		case let .folder(folder):
			id = folder.id
			type = "folder"
			name = folder.name
			path = folder.path
			children = folder.children.map { TreeNodeResponse(from: $0) }
		case let .file(file):
			id = file.id
			type = "file"
			name = file.name
			path = file.path
			children = nil
		}
	}
}

// MARK: - Categories Tree (CategoriesNode wrappers)

nonisolated struct CategoriesNodeResponse: Codable, Sendable {
	let id: String
	let type: String // "section", "declaration", "syntheticRoot"
	let title: String?
	let displayName: String?
	let containerPath: String?
	let filePath: String?
	let line: Int?
	let isView: Bool?
	let relationship: String?
	let conformances: String?
	let children: [CategoriesNodeResponse]
	// Icon serialization for cache round-tripping
	let typeIconSystemName: String?
	let typeIconEmoji: String?
}

extension CategoriesNodeResponse {
	init(from node: CategoriesNode) {
		switch node {
		case let .section(section):
			id = section.id.rawValue
			type = "section"
			title = section.title
			displayName = nil
			containerPath = nil
			filePath = nil
			line = nil
			isView = nil
			relationship = nil
			conformances = nil
			typeIconSystemName = nil
			typeIconEmoji = nil
			children = section.children.map { CategoriesNodeResponse(from: $0) }
		case let .declaration(decl):
			id = decl.id
			type = "declaration"
			title = nil
			displayName = decl.displayName
			containerPath = decl.containerPath
			filePath = decl.locationInfo.relativePath
			line = decl.locationInfo.line
			isView = decl.isView
			relationship = decl.relationship?.rawValue
			conformances = decl.conformances
			(typeIconSystemName, typeIconEmoji) = decl.typeIcon.serializableComponents
			children = decl.children.map { CategoriesNodeResponse(from: $0) }
		case let .syntheticRoot(root):
			id = root.id
			type = "syntheticRoot"
			title = root.title
			displayName = nil
			containerPath = nil
			filePath = nil
			line = nil
			isView = nil
			relationship = nil
			conformances = nil
			(typeIconSystemName, typeIconEmoji) = root.icon.serializableComponents
			children = root.children.map { CategoriesNodeResponse(from: $0) }
		}
	}
}

// MARK: - Files Tree (FileBrowserNode wrappers)

nonisolated struct FileBrowserNodeResponse: Codable, Sendable {
	let id: String
	let type: String // "directory" or "file"
	let name: String
	let path: String?
	let containsSwiftFiles: Bool?
	let usageBadge: String?
	let children: [FileBrowserNodeResponse]?
}

extension FileBrowserNodeResponse {
	init(from node: FileBrowserNode) {
		switch node {
		case let .directory(dir):
			id = dir.id
			type = "directory"
			name = dir.name
			path = nil
			containsSwiftFiles = dir.containsSwiftFiles
			usageBadge = nil
			children = dir.children.map { FileBrowserNodeResponse(from: $0) }
		case let .file(file):
			id = file.id
			type = "file"
			name = file.name
			path = file.path
			containsSwiftFiles = nil
			usageBadge = file.usageBadge
				.map { "\($0.text) (\($0.isWarning ? "warning" : $0.isPositive ? "positive" : "neutral"))" }
			children = nil
		}
	}
}

// MARK: - Summary

nonisolated struct ScanSummaryResponse: Codable, Sendable {
	let totalCount: Int
	let byAnnotation: [String: Int]
}

extension ScanSummaryResponse {
	init(from results: [ScanResult]) {
		totalCount = results.count
		var counts: [String: Int] = [:]
		for result in results {
			let key = switch result.annotation {
			case .unused: "unused"
			case .assignOnlyProperty: "assignOnlyProperty"
			case .redundantProtocol: "redundantProtocol"
			case .redundantPublicAccessibility: "redundantPublicAccessibility"
			case .redundantInternalAccessibility: "redundantInternalAccessibility"
			case .redundantFilePrivateAccessibility: "redundantFilePrivateAccessibility"
			case .superfluousIgnoreCommand: "superfluousIgnoreCommand"
			case .redundantAccessibility: "redundantAccessibility"
			}
			counts[key, default: 0] += 1
		}
		byAnnotation = counts
	}
}
