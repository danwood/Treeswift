//
//  DeletionOperationExecutor.swift
//  Treeswift
//
//  Centralized executor for code deletion and modification operations.
//

import Cocoa
import Foundation
import SourceGraph
import SystemPackage

/**
 Executes file modification operations with undo/redo support.

 Handles the full lifecycle of code modifications:
 - File reading/writing
 - Cache invalidation
 - Source graph line adjustments
 - Undo/redo registration
 - State management callbacks

 This executor is UI-agnostic and can be used from any context.
 */
struct DeletionOperationExecutor {
	/**
	 Executes declaration deletion with smart boundary detection.

	 Deletes a declaration from source code, including its attributes and comments.
	 Handles source graph line number adjustments and registers undo/redo.
	 */
	@MainActor
	static func executeDeclarationDeletion(
		declaration: Declaration,
		location: Location,
		sourceGraph: SourceGraph?,
		undoManager: UndoManager?,
		warningID: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) -> Result<Void, Error> {
		let filePath = location.file.path.string

		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(NSError(
				domain: "DeletionOperationExecutor",
				code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Failed to read file"]
			))
		}

		// Use helper for smart deletion
		let result = DeclarationDeletionHelper.deleteDeclaration(declaration: declaration)

		switch result {
		case let .success(deletionRange):
			// Invalidate source file cache
			SourceFileReader.invalidateCache(for: filePath)

			// Adjust line numbers and track which declarations were adjusted
			let linesRemoved = deletionRange.endLine - deletionRange.startLine + 1
			let afterLine = deletionRange.endLine

			let adjustedUSRs: [String] = if let sourceGraph {
				SourceGraphLineAdjuster.adjustAndTrack(
					sourceGraph: sourceGraph,
					filePath: filePath,
					afterLine: afterLine,
					lineDelta: -linesRemoved
				)
			} else {
				[]
			}

			// Get modified contents after deletion
			guard let modifiedContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
				return .failure(NSError(
					domain: "DeletionOperationExecutor",
					code: 2,
					userInfo: [NSLocalizedDescriptionKey: "Failed to read modified file"]
				))
			}

			// Register undo
			UndoRedoHelper.registerDeletionUndo(
				undoManager: undoManager,
				originalContents: originalContents,
				modifiedContents: modifiedContents,
				filePath: filePath,
				warningID: warningID,
				adjustedUSRs: adjustedUSRs,
				lineAdjustment: linesRemoved,
				sourceGraph: sourceGraph,
				actionName: "Delete Declaration",
				onComplete: onComplete,
				onRestore: onRestore
			)

			// Call completion callback
			onComplete()

			return .success(())

		case let .failure(error):
			return .failure(error)
		}
	}

	/**
	 Executes simple declaration deletion without smart boundary detection.

	 Falls back to basic line-range deletion when sourceGraph is unavailable.
	 Used when the declaration has full range info but no sourceGraph context.
	 */
	@MainActor
	static func executeSimpleDeclarationDeletion(
		declaration: Declaration,
		location: Location,
		sourceGraph: SourceGraph?,
		undoManager: UndoManager?,
		warningID: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) -> Result<Void, Error> {
		guard let endLine = location.endLine, location.endColumn != nil else {
			return .failure(NSError(
				domain: "DeletionOperationExecutor",
				code: 3,
				userInfo: [NSLocalizedDescriptionKey: "Missing end line/column"]
			))
		}

		let filePath = location.file.path.string

		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(NSError(
				domain: "DeletionOperationExecutor",
				code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Failed to read file"]
			))
		}

		// Delete the declaration range
		var lines = originalContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(NSError(
				domain: "DeletionOperationExecutor",
				code: 4,
				userInfo: [NSLocalizedDescriptionKey: "Invalid line range"]
			))
		}
		guard endLine > 0, endLine <= lines.count else {
			return .failure(NSError(
				domain: "DeletionOperationExecutor",
				code: 4,
				userInfo: [NSLocalizedDescriptionKey: "Invalid end line"]
			))
		}

		// Remove lines from startLine to endLine (inclusive)
		let startIndex = location.line - 1
		let endIndex = endLine - 1
		lines.removeSubrange(startIndex ... endIndex)

		// Write back to file
		let newContents = lines.joined(separator: "\n")
		do {
			try newContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(error)
		}

		// Invalidate source file cache
		SourceFileReader.invalidateCache(for: filePath)

		// Adjust line numbers and track which declarations were adjusted
		let linesRemoved = endLine - location.line + 1
		let afterLine = endLine

		let adjustedUSRs: [String] = if let sourceGraph {
			SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: sourceGraph,
				filePath: filePath,
				afterLine: afterLine,
				lineDelta: -linesRemoved
			)
		} else {
			[]
		}

		// Register undo
		UndoRedoHelper.registerDeletionUndo(
			undoManager: undoManager,
			originalContents: originalContents,
			modifiedContents: newContents,
			filePath: filePath,
			warningID: warningID,
			adjustedUSRs: adjustedUSRs,
			lineAdjustment: linesRemoved,
			sourceGraph: sourceGraph,
			actionName: "Delete Declaration",
			onComplete: onComplete,
			onRestore: onRestore
		)

		// Call completion callback
		onComplete()

		return .success(())
	}

	/**
	 Executes import statement deletion.

	 Deletes a single import line and adjusts line numbers in the source graph.
	 */
	@MainActor
	static func executeImportDeletion(
		location: Location,
		sourceGraph: SourceGraph?,
		undoManager: UndoManager?,
		warningID: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) -> Result<Void, Error> {
		let filePath = location.file.path.string

		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(NSError(
				domain: "DeletionOperationExecutor",
				code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Failed to read file"]
			))
		}

		// Delete the single import line
		var lines = originalContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(NSError(
				domain: "DeletionOperationExecutor",
				code: 4,
				userInfo: [NSLocalizedDescriptionKey: "Invalid line number"]
			))
		}

		// Remove the import line
		let lineIndex = location.line - 1
		lines.remove(at: lineIndex)

		// Write back to file
		let newContents = lines.joined(separator: "\n")
		do {
			try newContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(error)
		}

		// Invalidate source file cache
		SourceFileReader.invalidateCache(for: filePath)

		// Adjust line numbers and track which declarations were adjusted
		let afterLine = location.line

		let adjustedUSRs: [String] = if let sourceGraph {
			SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: sourceGraph,
				filePath: filePath,
				afterLine: afterLine,
				lineDelta: -1 // Removed one line
			)
		} else {
			[]
		}

		// Register undo
		UndoRedoHelper.registerDeletionUndo(
			undoManager: undoManager,
			originalContents: originalContents,
			modifiedContents: newContents,
			filePath: filePath,
			warningID: warningID,
			adjustedUSRs: adjustedUSRs,
			lineAdjustment: 1, // One line removed
			sourceGraph: sourceGraph,
			actionName: "Delete Import",
			onComplete: onComplete,
			onRestore: onRestore
		)

		// Call completion callback
		onComplete()

		return .success(())
	}

	/**
	 Executes ignore directive insertion.

	 Inserts a "// periphery:ignore" comment above the declaration,
	 including attributes and comments. Adjusts line numbers and registers undo/redo.
	 */
	@MainActor
	static func executeIgnoreDirectiveInsertion(
		declaration: Declaration,
		location: Location,
		sourceGraph: SourceGraph?,
		undoManager: UndoManager?,
		warningID: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) -> Result<Void, Error> {
		let filePath = location.file.path.string

		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(NSError(
				domain: "DeletionOperationExecutor",
				code: 1,
				userInfo: [NSLocalizedDescriptionKey: "Failed to read file"]
			))
		}

		var lines = originalContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(NSError(
				domain: "DeletionOperationExecutor",
				code: 4,
				userInfo: [NSLocalizedDescriptionKey: "Invalid line number"]
			))
		}

		// Find the insertion line (same as deletion start line logic)
		let insertionLine = DeclarationDeletionHelper.findDeletionStartLine(
			lines: lines,
			declarationLine: location.line,
			attributes: declaration.attributes
		)

		// Insert the ignore directive
		let insertIndex = insertionLine - 1
		lines.insert("// periphery:ignore", at: insertIndex)

		// Write back to file
		let modifiedContents = lines.joined(separator: "\n")
		do {
			try modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(error)
		}

		// Invalidate cache
		SourceFileReader.invalidateCache(for: filePath)

		// Adjust line numbers for declarations after this one
		let adjustedUSRs: [String] = if let sourceGraph {
			SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: sourceGraph,
				filePath: filePath,
				afterLine: insertionLine - 1, // Line before insertion
				lineDelta: 1 // Added one line
			)
		} else {
			[]
		}

		// Register undo (note: for insertion, we negate the line adjustment)
		UndoRedoHelper.registerDeletionUndo(
			undoManager: undoManager,
			originalContents: originalContents,
			modifiedContents: modifiedContents,
			filePath: filePath,
			warningID: warningID,
			adjustedUSRs: adjustedUSRs,
			lineAdjustment: -1, // Negative because we added a line (undo removes it)
			sourceGraph: sourceGraph,
			actionName: "Insert Ignore Directive",
			onComplete: onComplete,
			onRestore: onRestore
		)

		// Call completion callback
		onComplete()

		return .success(())
	}
}
