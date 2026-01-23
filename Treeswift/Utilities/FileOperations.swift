//
//  FileOperations.swift
//  Treeswift
//
//  Utilities for file system operations (move, rename)
//

import AppKit
import Foundation

private enum FileOperationError: LocalizedError, Sendable {
	case sourceNotFound(String)
	case targetAlreadyExists(String)
	case invalidPath(String)
	case operationFailed(String, Error)

	var errorDescription: String? {
		switch self {
		case let .sourceNotFound(path):
			"Source not found: \(path)"
		case let .targetAlreadyExists(path):
			"Target already exists: \(path)"
		case let .invalidPath(path):
			"Invalid path: \(path)"
		case let .operationFailed(operation, error):
			"\(operation) failed: \(error.localizedDescription)"
		}
	}
}

/// Organize a view and its children into a dedicated folder
///
/// This function:
/// 1. Creates a new folder with the view's name
/// 2. Moves the view file into that folder
/// 3. Moves all child items (files/folders) into that folder
/// 4. Registers a single compound undo action that reverses all moves
///
/// - Parameters:
///   - viewFilePath: Full path to the parent view's .swift file
///   - newFolderPath: Full path where the new folder should be created
///   - itemsToMove: Full paths of child items (files/folders) to move into the new folder
///   - undoManager: Optional undo manager to register undo action
func organizeViewIntoFolder(
	viewFilePath: String,
	newFolderPath: String,
	itemsToMove: [String],
	undoManager: UndoManager? = nil
) throws {
	let fileManager = FileManager.default
	let viewFileName = (viewFilePath as NSString).lastPathComponent

	// Validate view file exists
	guard fileManager.fileExists(atPath: viewFilePath) else {
		throw FileOperationError.sourceNotFound(viewFilePath)
	}

	// Check if folder already exists
	if fileManager.fileExists(atPath: newFolderPath) {
		throw FileOperationError.targetAlreadyExists(newFolderPath)
	}

	// Validate all items to move exist
	for itemPath in itemsToMove {
		guard fileManager.fileExists(atPath: itemPath) else {
			throw FileOperationError.sourceNotFound(itemPath)
		}
	}

	// Track what was moved for undo
	var movedItems: [(originalPath: String, newPath: String)] = []

	do {
		// Step 1: Create the folder
		try fileManager.createDirectory(atPath: newFolderPath, withIntermediateDirectories: false, attributes: nil)

		// Step 2: Move the view file into the new folder
		let viewFileNewPath = (newFolderPath as NSString).appendingPathComponent(viewFileName)
		try fileManager.moveItem(atPath: viewFilePath, toPath: viewFileNewPath)
		movedItems.append((viewFilePath, viewFileNewPath))

		// Step 3: Move all child items into the new folder
		for itemPath in itemsToMove {
			let itemName = (itemPath as NSString).lastPathComponent
			let itemNewPath = (newFolderPath as NSString).appendingPathComponent(itemName)

			// Skip if item is already inside the new folder (shouldn't happen but be safe)
			if itemPath.hasPrefix(newFolderPath) {
				continue
			}

			// Skip if target already exists (could be duplicate entries)
			if fileManager.fileExists(atPath: itemNewPath) {
				continue
			}

			try fileManager.moveItem(atPath: itemPath, toPath: itemNewPath)
			movedItems.append((itemPath, itemNewPath))
		}

		// Register compound undo operation
		undoManager?.registerUndo(withTarget: NSObject()) { _ in
			do {
				// Move items back in reverse order
				for (originalPath, newPath) in movedItems.reversed() {
					if fileManager.fileExists(atPath: newPath) {
						let originalFolder = (originalPath as NSString).deletingLastPathComponent
						// Ensure original folder exists
						if !fileManager.fileExists(atPath: originalFolder) {
							try fileManager.createDirectory(
								atPath: originalFolder,
								withIntermediateDirectories: true,
								attributes: nil
							)
						}
						try fileManager.moveItem(atPath: newPath, toPath: originalPath)
					}
				}

				// Remove the created folder if it's now empty
				let contents = try fileManager.contentsOfDirectory(atPath: newFolderPath)
				if contents.isEmpty {
					try fileManager.removeItem(atPath: newFolderPath)
				}
			} catch {
				showErrorAlert(message: "Cannot undo: \(error.localizedDescription)")
			}
		}
		undoManager?.setActionName("Organize '\((newFolderPath as NSString).lastPathComponent)' into Folder")

	} catch {
		// Rollback: try to undo any moves that succeeded
		for (originalPath, newPath) in movedItems.reversed() {
			try? fileManager.moveItem(atPath: newPath, toPath: originalPath)
		}
		// Remove the folder if it was created
		if fileManager.fileExists(atPath: newFolderPath) {
			let contents = try? fileManager.contentsOfDirectory(atPath: newFolderPath)
			if contents?.isEmpty == true {
				try? fileManager.removeItem(atPath: newFolderPath)
			}
		}
		throw FileOperationError.operationFailed("Organize view into folder", error)
	}
}

/// Show error alert for failed operations
@MainActor
private func showErrorAlert(message: String) {
	let alert = NSAlert()
	alert.messageText = "Operation Failed"
	alert.informativeText = message
	alert.alertStyle = .warning
	alert.addButton(withTitle: "OK")
	alert.runModal()
}
