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
	 Removes all unused code from this file.

	 Processes warnings from bottom to top to maintain line number consistency.
	 Only removes code for warnings where canRemoveCode returns true.
	 Tracks all file modifications and line adjustments for undo/redo support.
	 */
	func removeAllUnusedCode(
		scanResults: [ScanResult],
		filterState: FilterState?,
		sourceGraph: SourceGraph?
	) -> Result<RemovalResult, Error> {
		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: path, encoding: .utf8) else {
			return .failure(NSError(
				domain: "FileNode",
				code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Cannot read file"]
			))
		}

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

				// Match file path
				guard location.file.path.string == path else { return nil }

				// Apply filter state if provided
				if let filterState {
					guard filterState.shouldShow(scanResult: scanResult, declaration: declaration) else {
						return nil
					}
				}

				// Check if code can be removed for this warning
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
				// Sort bottom to top (highest line first)
				if lhs.location.line != rhs.location.line {
					return lhs.location.line > rhs.location.line
				}
				return lhs.location.column > rhs.location.column
			}

		// If no warnings can be removed, return early
		guard !fileWarnings.isEmpty else {
			return .failure(NSError(
				domain: "FileNode",
				code: 2,
				userInfo: [NSLocalizedDescriptionKey: "No removable warnings found"]
			))
		}

		// Use the batch modification helper to process all warnings
		let result = CodeModificationHelper.executeBatchModifications(
			operations: fileWarnings,
			filePath: path,
			sourceGraph: sourceGraph
		)

		// Add non-deletable count to the result
		switch result {
		case var .success(removalResult):
			// Update deletion stats to include non-deletable count
			var updatedStats = removalResult.deletionStats
			updatedStats = DeletionStats(
				deletedCount: updatedStats.deletedCount,
				nonDeletableCount: nonDeletableCount,
				failedIgnoreCommentsCount: updatedStats.failedIgnoreCommentsCount
			)

			let updatedResult = RemovalResult(
				filePath: removalResult.filePath,
				originalContents: removalResult.originalContents,
				modifiedContents: removalResult.modifiedContents,
				removedWarningIDs: removalResult.removedWarningIDs,
				adjustedUSRs: removalResult.adjustedUSRs,
				shouldDeleteFile: removalResult.shouldDeleteFile,
				shouldRemoveImports: removalResult.shouldRemoveImports,
				deletionStats: updatedStats
			)

			return .success(updatedResult)

		case let .failure(error):
			return .failure(error)
		}
	}
}
