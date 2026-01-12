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
	case error
}

nonisolated struct AnalysisWarning: Hashable, Sendable {
	let severity: WarningSeverity
	let message: String
	/// Dictionary mapping suggested actions to their completion status.
	/// Bool value indicates whether the action has been completed:
	/// - false (default): Action has not been performed yet
	/// - true: Action has been completed
	/// This allows tracking which suggested actions have been applied.
	let suggestedActions: [SuggestedAction: Bool]
	let details: [String]?
	let symbolReferences: [SymbolReference]?

	init(severity: WarningSeverity, message: String, suggestedActions: [SuggestedAction] = [], details: [String]? = nil, symbolReferences: [SymbolReference]? = nil) {
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

	var displayText: String {
		switch self {
		case .moveSymbolsToFolder(let symbols, let target):
			if symbols.count == 1 {
				return "Move \(symbols[0]) to \(target.displayName)"
			} else {
				return "Move \(symbols.count) symbols to \(target.displayName)"
			}
		case .moveFileToFolder(_, let fileName, let target):
			return "Move \(fileName) to \(target.displayName)"
		case .moveFolderIntoFolder(_, let sourceName, let target):
			return "Move \(sourceName)/ into \(target.displayName)"
		case .renameFolder(_, let suggestedName):
			return "Rename folder to '\(suggestedName)'"
		case .splitFolderIntoSubfolders(_, let suggestion):
			return "Split into subfolders (\(suggestion))"
		case .refactorToUseMainSymbol(_, let mainSymbol, _):
			return "Refactor to use only \(mainSymbol)"
		case .checkEncapsulation(_, let reason):
			return "Check encapsulation: \(reason)"
		case .renameFileToMatchSymbol(_, _, let suggestedName):
			return "Rename file to '\(suggestedName)'"
		case .moveFileToTrash(_, let fileName):
			return "Move '\(fileName)' to Trash"
		}
	}
}

nonisolated struct FolderTarget: Hashable, Sendable {
	let folderPath: String
	let folderName: String

	var displayName: String {
		return folderName + "/"
	}
}

nonisolated struct SymbolReference: Hashable, Sendable {
	let symbolName: String
	let icon: String
	let filePath: String
	let line: Int
	let shouldBePublic: Bool
}
