//
//  Warnings.swift
//  Treeswift
//
//  Warning and suggested action types for folder/file analysis
//

import Foundation

nonisolated enum WarningSeverity: Hashable, Sendable {
	case info
	case warning
}

nonisolated struct AnalysisWarning: Hashable, Sendable {
	private let severity: WarningSeverity
	private let message: String
	/// Dictionary mapping suggested actions to their completion status.
	/// Bool value indicates whether the action has been completed:
	/// - false (default): Action has not been performed yet
	/// - true: Action has been completed
	/// This allows tracking which suggested actions have been applied.
	private let suggestedActions: [SuggestedAction: Bool]
	private let details: [String]?
	private let symbolReferences: [SymbolReference]?

	init(
		severity: WarningSeverity,
		message: String,
		suggestedActions: [SuggestedAction] = [],
		details: [String]? = nil,
		symbolReferences: [SymbolReference]? = nil
	) {
		self.severity = severity
		self.message = message
		// Initialize all actions as incomplete (false)
		self.suggestedActions = Dictionary(uniqueKeysWithValues: suggestedActions.map { ($0, false) })
		self.details = details
		self.symbolReferences = symbolReferences
	}
}

nonisolated enum SuggestedAction: Hashable, Sendable {
	case moveSymbolsToFolder(symbols: [String], targetFolder: FolderTarget)
	case moveFileToFolder(filePath: String, fileName: String, targetFolder: FolderTarget)
	case moveFolderIntoFolder(sourceFolderPath: String, sourceFolderName: String, targetFolder: FolderTarget)
	case renameFolder(currentPath: String, suggestedName: String)
	case splitFolderIntoSubfolders(folderPath: String, suggestion: String)
	case refactorToUseMainSymbol(folderPath: String, mainSymbol: String, leakedSymbols: [String])
	case checkEncapsulation(folderPath: String, reason: String)
	case renameFileToMatchSymbol(currentPath: String, currentName: String, suggestedName: String)
	case moveFileToTrash(filePath: String, fileName: String)
}

nonisolated struct FolderTarget: Hashable, Sendable {
	let folderPath: String
	let folderName: String
}

nonisolated struct SymbolReference: Hashable, Sendable {
	let symbolName: String
	let icon: String
	let filePath: String
	let line: Int
	let shouldBePublic: Bool
}
