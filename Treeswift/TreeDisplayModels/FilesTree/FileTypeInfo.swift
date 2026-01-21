//
//  FileTypeInfo.swift
//  Treeswift
//
//  Information about a type defined in a file
//

import Foundation

nonisolated struct FileTypeInfo: Hashable, Sendable {
	let name: String
	let icon: String
	let matchesFileName: Bool
	let warningTypes: Set<FilterState.WarningType>
	let isExtension: Bool
	let referencingFileNames: [String]
	let startLine: Int

	init(
		name: String,
		icon: String,
		matchesFileName: Bool,
		warningTypes: Set<FilterState.WarningType>,
		isExtension: Bool,
		referencingFileNames: [String] = [],
		startLine: Int = 0
	) {
		self.name = name
		self.icon = icon
		self.matchesFileName = matchesFileName
		self.warningTypes = warningTypes
		self.isExtension = isExtension
		self.referencingFileNames = referencingFileNames
		self.startLine = startLine
	}
}
