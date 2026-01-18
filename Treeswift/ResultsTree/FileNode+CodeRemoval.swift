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
	 Result of removing all unused code from a file.
	 */
	struct RemovalResult {
		let filePath: String
		let originalContents: String
		let modifiedContents: String
		let removedWarningIDs: [String]
		let adjustedUSRs: [String]
		let lineAdjustments: [Int]
		let shouldDeleteFile: Bool
		let shouldRemoveImports: Bool
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

		// Filter and sort warnings for this file (bottom to top)
		let fileWarnings = scanResults
			.compactMap { result -> (result: ScanResult, declaration: Declaration, location: Location)? in
				let declaration = result.declaration
				let location = ScanResultHelper.location(from: declaration)

				// Match file path
				guard location.file.path.string == path else { return nil }

				// Apply filter state if provided
				if let filterState {
					guard filterState.shouldShow(result: result, declaration: declaration) else {
						return nil
					}
				}

				// Check if code can be removed for this warning
				let hasFullRange = location.endLine != nil && location.endColumn != nil
				let isImport = declaration.kind == .module
				guard result.annotation.canRemoveCode(hasFullRange: hasFullRange, isImport: isImport) else {
					return nil
				}

				return (result, declaration, location)
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

		// Process each warning from bottom to top
		var currentContents = originalContents
		var removedWarningIDs: [String] = []
		var adjustedUSRs: [String] = []
		var lineAdjustments: [Int] = []

		for (result, declaration, location) in fileWarnings {
			// Generate warning ID
			let usr = declaration.usrs.first ?? ""
			let warningID = "\(location.file.path.string):\(usr)"

			// Handle redundant public separately
			if case .redundantPublicAccessibility = result.annotation {
				let removalResult = removeRedundantPublic(
					declaration: declaration,
					location: location,
					currentContents: currentContents
				)

				switch removalResult {
				case let .success(newContents):
					currentContents = newContents
					removedWarningIDs.append(warningID)
					lineAdjustments.append(0)
				case .failure:
					continue
				}
			} else if result.annotation == .superfluousIgnoreCommand {
				// Handle superfluous ignore comment deletion
				let removalResult = removeSuperfluousIgnore(
					declaration: declaration,
					location: location,
					currentContents: currentContents,
					sourceGraph: sourceGraph
				)

				switch removalResult {
				case .success(let (newContents, linesRemoved, adjustedUSR)):
					currentContents = newContents
					removedWarningIDs.append(warningID)
					if !adjustedUSR.isEmpty {
						adjustedUSRs.append(contentsOf: adjustedUSR)
					}
					lineAdjustments.append(linesRemoved)
				case .failure:
					continue
				}
			} else if declaration.kind == .module {
				// Handle import deletion
				let removalResult = removeImport(
					location: location,
					currentContents: currentContents,
					sourceGraph: sourceGraph
				)

				switch removalResult {
				case .success(let (newContents, adjustedUSR)):
					currentContents = newContents
					removedWarningIDs.append(warningID)
					if !adjustedUSR.isEmpty {
						adjustedUSRs.append(contentsOf: adjustedUSR)
					}
					lineAdjustments.append(1)
				case .failure:
					continue
				}
			} else {
				// Handle declaration deletion
				let removalResult = removeDeclaration(
					declaration: declaration,
					currentContents: currentContents,
					sourceGraph: sourceGraph
				)

				switch removalResult {
				case .success(let (newContents, linesRemoved, adjustedUSR)):
					currentContents = newContents
					removedWarningIDs.append(warningID)
					if !adjustedUSR.isEmpty {
						adjustedUSRs.append(contentsOf: adjustedUSR)
					}
					lineAdjustments.append(linesRemoved)
				case .failure:
					continue
				}
			}
		}

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
			adjustedUSRs: adjustedUSRs,
			lineAdjustments: lineAdjustments,
			shouldDeleteFile: shouldDeleteFile,
			shouldRemoveImports: shouldRemoveImports
		))
	}

	/**
	 Removes redundant public keyword from a declaration.
	 */
	private func removeRedundantPublic(
		declaration: Declaration,
		location: Location,
		currentContents: String
	) -> Result<String, Error> {
		// Write current contents to file temporarily (for CodeModificationHelper)
		do {
			try currentContents.write(toFile: path, atomically: true, encoding: .utf8)
		} catch {
			return .failure(error)
		}

		let result = CodeModificationHelper.removeRedundantPublic(
			declaration: declaration,
			location: location
		)

		switch result {
		case let .success(modification):
			return .success(modification.modifiedContents)
		case let .failure(error):
			return .failure(error)
		}
	}

	/**
	 Removes an import statement.
	 */
	private func removeImport(
		location: Location,
		currentContents: String,
		sourceGraph: SourceGraph?
	) -> Result<(String, [String]), Error> {
		var lines = currentContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(NSError(
				domain: "FileNode",
				code: 5,
				userInfo: [NSLocalizedDescriptionKey: "Invalid line number"]
			))
		}

		let lineIndex = location.line - 1
		lines.remove(at: lineIndex)

		let newContents = lines.joined(separator: "\n")

		// Track adjusted USRs for line number updates
		let adjustedUSRs = sourceGraph.map {
			SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: $0,
				filePath: path,
				afterLine: location.line,
				lineDelta: -1 // Removed one line
			)
		} ?? []

		return .success((newContents, adjustedUSRs))
	}

	/**
	 Removes a superfluous periphery:ignore comment.
	 */
	private func removeSuperfluousIgnore(
		declaration: Declaration,
		location: Location,
		currentContents: String,
		sourceGraph: SourceGraph?
	) -> Result<(String, Int, [String]), Error> {
		// Write current contents to file temporarily
		do {
			try currentContents.write(toFile: path, atomically: true, encoding: .utf8)
		} catch {
			return .failure(error)
		}

		let result = CodeModificationHelper.removeSuperfluousIgnoreComment(
			declaration: declaration,
			location: location
		)

		switch result {
		case let .success(modification):
			// Use ModificationResult helper to adjust source graph
			let adjustedUSRs = sourceGraph.map { modification.adjustSourceGraph($0) } ?? []

			return .success((modification.modifiedContents, modification.linesRemoved, adjustedUSRs))

		case let .failure(error):
			return .failure(error)
		}
	}

	/**
	 Removes a declaration using DeclarationDeletionHelper.
	 */
	private func removeDeclaration(
		declaration: Declaration,
		currentContents: String,
		sourceGraph: SourceGraph?
	) -> Result<(String, Int, [String]), Error> {
		// Write current contents to file temporarily
		do {
			try currentContents.write(toFile: path, atomically: true, encoding: .utf8)
		} catch {
			return .failure(error)
		}

		// Use DeclarationDeletionHelper to delete
		let result = DeclarationDeletionHelper.deleteDeclaration(declaration: declaration)

		switch result {
		case let .success(deletionRange):
			let linesRemoved = deletionRange.endLine - deletionRange.startLine + 1

			// Read modified contents
			guard let modifiedContents = try? String(contentsOfFile: path, encoding: .utf8) else {
				return .failure(NSError(
					domain: "FileNode",
					code: 6,
					userInfo: [NSLocalizedDescriptionKey: "Cannot read modified file"]
				))
			}

			// Track adjusted USRs for line number updates
			let adjustedUSRs = sourceGraph.map {
				SourceGraphLineAdjuster.adjustAndTrack(
					sourceGraph: $0,
					filePath: path,
					afterLine: deletionRange.endLine,
					lineDelta: -linesRemoved
				)
			} ?? []

			return .success((modifiedContents, linesRemoved, adjustedUSRs))

		case let .failure(error):
			return .failure(error)
		}
	}
}
