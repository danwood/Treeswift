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
		let shouldDeleteFile: Bool
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
			return !result.annotation.canRemoveCode(hasFullRange: hasFullRange, isImport: isImport)
		}
		let nonDeletableCount = nonDeletableWarnings.count

		// Filter and sort warnings for this file (bottom to top)
		let fileWarnings = scanResults
			.compactMap { scanResult -> (result: ScanResult, declaration: Declaration, location: Location)? in
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
				guard scanResult.annotation.canRemoveCode(hasFullRange: hasFullRange, isImport: isImport) else {
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

		// Split contents into lines ONCE for in-memory processing
		// This prevents line number staleness that occurs with disk-based deletion
		var lines = originalContents.components(separatedBy: .newlines)
		var removedWarningIDs: [String] = []
		var adjustedUSRs: [String] = []
		var failedIgnoreCommentsCount = 0

		// Process each warning from bottom to top
		// Since sorted bottom-to-top, each deletion automatically shifts remaining correctly
		for (result, declaration, location) in fileWarnings {
			let usr = declaration.usrs.first ?? ""
			let warningID = "\(location.file.path.string):\(usr)"

			// Handle different removal types
			if case .redundantPublicAccessibility = result.annotation {
				// Remove "public " keyword from declaration line
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }

				let modifiedLine = lines[lineIndex].replacingOccurrences(
					of: #"public\s+"#,
					with: "",
					options: .regularExpression
				)
				lines[lineIndex] = modifiedLine
				removedWarningIDs.append(warningID)

			} else if result.annotation == .superfluousIgnoreCommand {
				// Find and remove periphery:ignore comment
				guard let commentLine = CommentScanner.findCommentContaining(
					pattern: "periphery:ignore",
					in: lines,
					backwardFrom: location.line,
					maxDistance: 10
				) else {
					failedIgnoreCommentsCount += 1
					continue
				}

				let commentIndex = commentLine - 1
				guard commentIndex >= 0, commentIndex < lines.count else { continue }

				lines.remove(at: commentIndex)
				removedWarningIDs.append(warningID)

				// Adjust source graph line numbers
				if let sourceGraph {
					let adjusted = SourceGraphLineAdjuster.adjustAndTrack(
						sourceGraph: sourceGraph,
						filePath: path,
						afterLine: commentLine,
						lineDelta: -1
					)
					adjustedUSRs.append(contentsOf: adjusted)
				}

			} else if declaration.kind == .module {
				// Remove import statement
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }

				lines.remove(at: lineIndex)
				removedWarningIDs.append(warningID)

				// Adjust source graph
				if let sourceGraph {
					let adjusted = SourceGraphLineAdjuster.adjustAndTrack(
						sourceGraph: sourceGraph,
						filePath: path,
						afterLine: location.line,
						lineDelta: -1
					)
					adjustedUSRs.append(contentsOf: adjusted)
				}

			} else {
				// Delete full declaration (struct, property, function, etc.)
				guard let endLine = location.endLine else { continue }

				// Find actual start line (including attributes and comments)
				let startLine = DeclarationDeletionHelper.findDeletionStartLine(
					lines: lines,
					declarationLine: location.line,
					attributes: declaration.attributes
				)

				// Include trailing blanks for multi-line declarations
				let isMultiLine = endLine > location.line
				let finalEndLine = isMultiLine
					? DeclarationDeletionHelper.findDeletionEndLine(
						lines: lines,
						declarationEndLine: endLine
					)
					: endLine

				// Validate range
				let startIndex = startLine - 1
				let endIndex = finalEndLine - 1
				guard startIndex >= 0, endIndex < lines.count, startIndex <= endIndex else {
					continue
				}

				// Remove lines from array
				let linesRemoved = endIndex - startIndex + 1
				lines.removeSubrange(startIndex ... endIndex)
				removedWarningIDs.append(warningID)

				// Adjust source graph
				if let sourceGraph {
					let adjusted = SourceGraphLineAdjuster.adjustAndTrack(
						sourceGraph: sourceGraph,
						filePath: path,
						afterLine: finalEndLine,
						lineDelta: -linesRemoved
					)
					adjustedUSRs.append(contentsOf: adjusted)
				}
			}
		}

		// Join lines back into string
		let currentContents = lines.joined(separator: "\n")

		// Determine if file should be deleted or if imports should be removed
		var shouldDeleteFile = false
		var shouldRemoveImports = false
		var finalContents = currentContents

		if let graph = sourceGraph {
			let analysisResult = FileContentAnalyzer.shouldDeleteFile(
				filePath: path,
				modifiedContents: currentContents,
				sourceGraph: graph,
				removedWarningIDs: removedWarningIDs
			)
			shouldDeleteFile = analysisResult.shouldDelete
			shouldRemoveImports = analysisResult.shouldRemoveImports

			// If keeping file only for comments, remove imports
			if shouldRemoveImports {
				finalContents = FileContentAnalyzer.removeImportStatements(from: currentContents)
			}
		}

		// Write modified contents to file
		do {
			try finalContents.write(toFile: path, atomically: true, encoding: .utf8)
		} catch {
			return .failure(error)
		}

		return .success(RemovalResult(
			filePath: path,
			originalContents: originalContents,
			modifiedContents: finalContents,
			removedWarningIDs: removedWarningIDs,
			shouldDeleteFile: shouldDeleteFile,
			deletionStats: DeletionStats(
				deletedCount: removedWarningIDs.count,
				nonDeletableCount: nonDeletableCount,
				failedIgnoreCommentsCount: failedIgnoreCommentsCount
			)
		))
	}
}
