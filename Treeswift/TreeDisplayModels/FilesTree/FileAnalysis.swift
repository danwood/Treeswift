//
//  FileAnalysis.swift
//  Treeswift
//
//  Analysis data for individual files (statistics, badges, symbol information)
//

import Foundation

nonisolated struct FileStatistics: Hashable, Sendable {
	let symbolCount: Int
	let externalReferenceCount: Int
	let externalFileCount: Int
	let folderReferenceCount: Int
	let sameFolderFileCount: Int
	let isEntryPoint: Bool
	let referencingFolders: [String]  // Folder names that reference this file (cross-folder)
	let sameFolderFileNames: [String]  // File names in same folder that reference this file

	var isFolderPrivate: Bool {
		let hasSymbols = symbolCount > 0
		let hasCrossFolderRefs = externalReferenceCount > 0
		let hasSameFolderRefs = sameFolderFileCount > 0
		return hasSymbols && hasSameFolderRefs && !hasCrossFolderRefs && !isEntryPoint
	}
}

nonisolated struct UsageBadge: Hashable, Sendable {
	let text: String
	let isWarning: Bool
	let isPositive: Bool
}
