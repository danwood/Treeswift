//
//  FileBrowserModels.swift
//  Treeswift
//
//  Core data models for file browser nodes (files and directories)
//

import Foundation

nonisolated enum FileBrowserNode: Identifiable, Hashable, Sendable {
	case directory(FileBrowserDirectory)
	case file(FileBrowserFile)

	var id: String {
		switch self {
		case let .directory(node): node.id
		case let .file(node): node.id
		}
	}

	// Collects all descendant IDs recursively
}

nonisolated struct FileBrowserDirectory: Identifiable, Hashable, Sendable {
	let id: String
	let name: String
	var children: [FileBrowserNode]
	var containsSwiftFiles: Bool

	init(
		id: String,
		name: String,
		children: [FileBrowserNode],
		containsSwiftFiles: Bool = true
	) {
		self.id = id
		self.name = name
		self.children = children
		self.containsSwiftFiles = containsSwiftFiles
	}
}

nonisolated struct FileBrowserFile: Identifiable, Hashable, Sendable {
	let id: String
	let name: String
	let path: String
	var typeInfos: [FileTypeInfo]?
	var analysisWarnings: [AnalysisWarning]
	var statistics: FileStatistics?
	var modificationDate: Date?
	var fileSize: Int64?

	init(
		id: String,
		name: String,
		path: String,
		typeInfos: [FileTypeInfo]? = nil,
		analysisWarnings: [AnalysisWarning] = [],
		statistics: FileStatistics? = nil,
		modificationDate: Date? = nil,
		fileSize: Int64? = nil
	) {
		self.id = id
		self.name = name
		self.path = path
		self.typeInfos = typeInfos
		self.analysisWarnings = analysisWarnings
		self.statistics = statistics
		self.modificationDate = modificationDate
		self.fileSize = fileSize
	}
}

extension FileBrowserNode: NavigableTreeNode {
	var navigationID: String { id }

	var isExpandable: Bool {
		if case .directory = self { return true }
		return false
	}

	var childNodes: [any NavigableTreeNode] {
		if case let .directory(dir) = self {
			return dir.children
		}
		return []
	}
}
