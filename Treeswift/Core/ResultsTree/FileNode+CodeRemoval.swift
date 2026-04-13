//
//  FileNode+CodeRemoval.swift
//  Treeswift
//
//  Extension to FileNode for removing unused code
//

import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

extension FileNode {
	/**
	 Statistics about deletion operations.
	 */
	struct DeletionStats {
		let deletedCount: Int
		let nonDeletableCount: Int
		let failedIgnoreCommentsCount: Int
		let skippedReferencedCount: Int
	}

	/**
	 Result of removing all unused code from a file.
	 */
	struct RemovalResult {
		let filePath: String
		let originalContents: String
		let modifiedContents: String
		let removedWarningIDs: [String]
		let adjustedUSRs: [String]
		let shouldDeleteFile: Bool
		let shouldRemoveImports: Bool
		let deletionStats: DeletionStats
	}

	/**
	 Computes the removal of all unused code from this file without writing to disk.

	 Returns a RemovalResult containing the planned modified contents and statistics.
	 Callers are responsible for writing modifiedContents to disk and handling undo/redo.
	 */
	func computeRemoval(
		scanResults: [ScanResult],
		filterState: FilterState?,
		sourceGraph: (any SourceGraphProtocol)?,
		strategy: RemovalStrategy = .forceRemoveAll,
		allUnusedDeclarations: Set<Declaration>? = nil,
		batchDeletionSet: Set<Declaration>? = nil
	) -> Result<RemovalResult, Error> {
		// Count total warnings in this file (for statistics)
		let allWarnings = scanResults.filter { scanResult in
			let declaration = scanResult.declaration
			let location = ScanResultHelper.location(from: declaration)
			guard location.file.path.string == path else { return false }
			if let filterState {
				guard filterState.shouldShow(scanResult: scanResult, declaration: declaration) else {
					return false
				}
			}
			return true
		}

		// Count non-deletable warnings
		let nonDeletableWarnings = allWarnings.filter { result in
			let declaration = result.declaration
			let location = ScanResultHelper.location(from: declaration)
			let hasFullRange = location.endLine != nil && location.endColumn != nil
			let isImport = declaration.kind == .module
			return !result.annotation.canRemoveCode(hasFullRange: hasFullRange, isImport: isImport, location: location)
		}
		let nonDeletableCount = nonDeletableWarnings.count

		// Filter and sort warnings for this file (bottom to top)
		let fileWarnings = scanResults
			.compactMap { scanResult -> (scanResult: ScanResult, declaration: Declaration, location: Location)? in
				let declaration = scanResult.declaration
				let location = ScanResultHelper.location(from: declaration)

				guard location.file.path.string == path else { return nil }

				if let filterState {
					guard filterState.shouldShow(scanResult: scanResult, declaration: declaration) else {
						return nil
					}
				}

				let hasFullRange = location.endLine != nil && location.endColumn != nil
				let isImport = declaration.kind == .module
				guard scanResult.annotation.canRemoveCode(
					hasFullRange: hasFullRange,
					isImport: isImport,
					location: location
				) else {
					return nil
				}

				return (scanResult, declaration, location)
			}
			.sorted { lhs, rhs in
				if lhs.location.line != rhs.location.line {
					return lhs.location.line > rhs.location.line
				}
				return lhs.location.column > rhs.location.column
			}

		guard !fileWarnings.isEmpty else {
			return .failure(NSError(
				domain: "FileNode",
				code: 2,
				userInfo: [NSLocalizedDescriptionKey: "No removable warnings found"]
			))
		}

		// Apply the removal strategy to filter operations
		let filtered = UnusedDependencyAnalyzer.filterOperations(
			operations: fileWarnings,
			strategy: strategy,
			sourceGraph: sourceGraph,
			allUnusedDeclarations: allUnusedDeclarations,
			batchDeletionSet: batchDeletionSet
		)
		let skippedReferencedCount = filtered.skippedCount
		let operationsToExecute = filtered.operationsToExecute

		guard !operationsToExecute.isEmpty else {
			return .failure(NSError(
				domain: "FileNode",
				code: 2,
				userInfo: [NSLocalizedDescriptionKey: "No removable warnings found"]
			))
		}

		let result = CodeModificationHelper.computeBatchModifications(
			operations: operationsToExecute,
			filePath: path,
			sourceGraph: sourceGraph
		)

		switch result {
		case let .success(batchResult):
			let updatedStats = DeletionStats(
				deletedCount: batchResult.removalResult.deletionStats.deletedCount,
				nonDeletableCount: nonDeletableCount,
				failedIgnoreCommentsCount: batchResult.removalResult.deletionStats.failedIgnoreCommentsCount,
				skippedReferencedCount: skippedReferencedCount
			)
			return .success(RemovalResult(
				filePath: batchResult.removalResult.filePath,
				originalContents: batchResult.removalResult.originalContents,
				modifiedContents: batchResult.removalResult.modifiedContents,
				removedWarningIDs: batchResult.removalResult.removedWarningIDs,
				adjustedUSRs: batchResult.removalResult.adjustedUSRs,
				shouldDeleteFile: batchResult.removalResult.shouldDeleteFile,
				shouldRemoveImports: batchResult.removalResult.shouldRemoveImports,
				deletionStats: updatedStats
			))
		case let .failure(error):
			return .failure(error)
		}
	}
}
