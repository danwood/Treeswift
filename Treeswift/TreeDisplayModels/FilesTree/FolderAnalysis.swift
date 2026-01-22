//
//  FolderAnalysis.swift
//  Treeswift
//
//  Analysis data for folder organization and statistics
//

import Foundation

nonisolated enum FolderType: Hashable, Sendable {
	case shared(symbolCount: Int)
	case symbol(mainSymbolName: String, icon: TreeIcon)
	case view(mainSymbolName: String?, icon: TreeIcon?)
	case ui
	case ambiguous
}

nonisolated struct FolderStatistics: Hashable, Sendable {
	let fileCount: Int
	let internalSymbolCount: Int
	let externalReferenceCount: Int
}
