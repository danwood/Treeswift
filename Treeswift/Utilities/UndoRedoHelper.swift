import Foundation
import Cocoa
import SourceGraph

/**
Helper for registering undo/redo operations for file modifications.

Handles the complex nested closure pattern required for proper undo/redo
with source graph line number adjustments.
*/
struct UndoRedoHelper {

	/**
	Registers undo for a file deletion with source graph updates.

	Handles the full undo/redo cycle including:
	- File content restoration
	- Source graph line number adjustments using SourceGraphLineAdjuster.reverseLineAdjustment
	- Cache invalidation
	- State callbacks (completion/restoration)
	*/
	static func registerDeletionUndo(
		undoManager: UndoManager?,
		originalContents: String,
		modifiedContents: String,
		filePath: String,
		warningID: String,
		adjustedUSRs: [String],
		lineAdjustment: Int,  // positive number (will be negated for undo)
		sourceGraph: SourceGraph?,
		actionName: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) {
		guard let undoManager = undoManager else { return }

		// Define the undo action
		@MainActor
		func performUndo() {
			try? originalContents.write(toFile: filePath, atomically: true, encoding: .utf8)
			SourceFileReader.invalidateCache(for: filePath)

			// Reverse line number adjustments using the helper
			if let sourceGraph = sourceGraph, !adjustedUSRs.isEmpty {
				SourceGraphLineAdjuster.reverseLineAdjustment(
					sourceGraph: sourceGraph,
					filePath: filePath,
					usrs: adjustedUSRs,
					adjustment: -lineAdjustment  // Reverse the adjustment
				)
			}

			onRestore()

			// Register redo
			undoManager.registerUndo(withTarget: NSObject()) { _ in
				performRedo()
			}
			undoManager.setActionName(actionName)
		}

		// Define the redo action
		@MainActor
		func performRedo() {
			try? modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
			SourceFileReader.invalidateCache(for: filePath)

			// Reapply line number adjustments using the helper
			if let sourceGraph = sourceGraph, !adjustedUSRs.isEmpty {
				SourceGraphLineAdjuster.reverseLineAdjustment(
					sourceGraph: sourceGraph,
					filePath: filePath,
					usrs: adjustedUSRs,
					adjustment: lineAdjustment  // Reapply the adjustment
				)
			}

			onComplete()

			// Register undo
			undoManager.registerUndo(withTarget: NSObject()) { _ in
				performUndo()
			}
			undoManager.setActionName(actionName)
		}

		// Register initial undo
		undoManager.registerUndo(withTarget: NSObject()) { _ in
			performUndo()
		}
		undoManager.setActionName(actionName)
	}

	/**
	Registers undo for a simple modification (no line number changes).

	Used for modifications that don't add or remove lines, such as
	removing the 'public' keyword or other in-place text replacements.
	*/
	static func registerModificationUndo(
		undoManager: UndoManager?,
		modification: CodeModificationHelper.ModificationResult,
		warningID: String,
		actionName: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) {
		guard let undoManager = undoManager else { return }

		undoManager.registerUndo(withTarget: NSObject()) { _ in
			try? modification.originalContents.write(
				toFile: modification.filePath,
				atomically: true,
				encoding: .utf8
			)
			SourceFileReader.invalidateCache(for: modification.filePath)
			onRestore()

			// Register redo
			undoManager.registerUndo(withTarget: NSObject()) { _ in
				try? modification.modifiedContents.write(
					toFile: modification.filePath,
					atomically: true,
					encoding: .utf8
				)
				SourceFileReader.invalidateCache(for: modification.filePath)
				onComplete()
			}
			undoManager.setActionName(actionName)
		}
		undoManager.setActionName(actionName)
	}

	/**
	Registers undo for a modification that changes line numbers.

	Handles modifications that add or remove lines and require source graph updates using SourceGraphLineAdjuster.reverseLineAdjustment.
	*/
	static func registerModificationUndoWithLineAdjustment(
		undoManager: UndoManager?,
		modification: CodeModificationHelper.ModificationResult,
		warningID: String,
		adjustedUSRs: [String],
		sourceGraph: SourceGraph?,
		actionName: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) {
		guard let undoManager = undoManager else { return }

		// Define the undo action
		@MainActor
		func performUndo() {
			// Restore file contents
			try? modification.originalContents.write(
				toFile: modification.filePath,
				atomically: true,
				encoding: .utf8
			)
			SourceFileReader.invalidateCache(for: modification.filePath)

			// Reverse line number adjustments using the helper
			if let sourceGraph = sourceGraph, !adjustedUSRs.isEmpty {
				SourceGraphLineAdjuster.reverseLineAdjustment(
					sourceGraph: sourceGraph,
					filePath: modification.filePath,
					usrs: adjustedUSRs,
					adjustment: -modification.linesRemoved  // Reverse the adjustment
				)
			}

			onRestore()

			// Register redo
			undoManager.registerUndo(withTarget: NSObject()) { _ in
				performRedo()
			}
			undoManager.setActionName(actionName)
		}

		// Define the redo action
		@MainActor
		func performRedo() {
			try? modification.modifiedContents.write(
				toFile: modification.filePath,
				atomically: true,
				encoding: .utf8
			)
			SourceFileReader.invalidateCache(for: modification.filePath)

			// Reapply line number adjustments using the helper
			if let sourceGraph = sourceGraph, !adjustedUSRs.isEmpty {
				SourceGraphLineAdjuster.reverseLineAdjustment(
					sourceGraph: sourceGraph,
					filePath: modification.filePath,
					usrs: adjustedUSRs,
					adjustment: modification.linesRemoved  // Reapply the adjustment
				)
			}

			onComplete()

			// Register undo
			undoManager.registerUndo(withTarget: NSObject()) { _ in
				performUndo()
			}
			undoManager.setActionName(actionName)
		}

		// Register initial undo
		undoManager.registerUndo(withTarget: NSObject()) { _ in
			performUndo()
		}
		undoManager.setActionName(actionName)
	}
}
