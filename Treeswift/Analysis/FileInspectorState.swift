//
//  FileInspectorState.swift
//  Treeswift
//
//  Tracks the currently inspected file and detects external changes
//

import SwiftUI

@Observable
@MainActor
final class FileInspectorState {
	// Currently inspected file path
	var inspectedFilePath: String?

	// Original file metadata when first inspected
	var originalModificationDate: Date?
	var originalFileSize: Int64?

	// Whether the inspected file has changed externally
	var fileHasChanged: Bool = false

	// Whether the file has been deleted
	var fileWasDeleted: Bool = false

	init() {}

	/*
	 Updates the currently inspected file and resets change detection

	 - Parameters:
	   - filePath: Path to the newly selected file, or nil if no file selected
	   - modificationDate: Modification date of the file
	   - fileSize: Size of the file in bytes
	 */
	func setInspectedFile(
		filePath: String?,
		modificationDate: Date?,
		fileSize: Int64?
	) {
		self.inspectedFilePath = filePath
		self.originalModificationDate = modificationDate
		self.originalFileSize = fileSize
		self.fileHasChanged = false
		self.fileWasDeleted = false
	}

	/*
	 Clears the currently inspected file
	 */
	func clearInspectedFile() {
		self.inspectedFilePath = nil
		self.originalModificationDate = nil
		self.originalFileSize = nil
		self.fileHasChanged = false
		self.fileWasDeleted = false
	}

	/*
	 Checks if the currently inspected file has been modified externally

	 Called when app returns to foreground to detect file changes
	 */
	func checkCurrentFile() {
		guard let filePath = inspectedFilePath else {
			return
		}

		let fileManager = FileManager.default

		// Check if file was deleted
		if !fileManager.fileExists(atPath: filePath) {
			fileWasDeleted = true
			fileHasChanged = false
			return
		}

		// Check if file has changed
		let hasChanged = fileManager.hasFileChanged(
			at: filePath,
			originalModificationDate: originalModificationDate,
			originalFileSize: originalFileSize
		)

		fileHasChanged = hasChanged
		fileWasDeleted = false
	}
}
