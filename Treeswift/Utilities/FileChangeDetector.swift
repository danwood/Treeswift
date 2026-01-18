//
//  FileChangeDetector.swift
//  Treeswift
//
//  Detects when files have been modified externally
//

import Foundation

extension FileManager {
	/*
	 Checks if a file has changed since the stored metadata was captured

	 - Parameters:
	   - filePath: Absolute path to the file to check
	   - originalModificationDate: The modification date when file was scanned
	   - originalFileSize: The file size when file was scanned

	 - Returns: `true` if file has changed, deleted, or cannot be accessed
	 */
	func hasFileChanged(
		at filePath: String,
		originalModificationDate: Date?,
		originalFileSize: Int64?
	) -> Bool {
		let fileURL = URL(fileURLWithPath: filePath)

		// Check if file exists
		guard fileExists(atPath: filePath) else {
			return true
		}

		// Get current file attributes
		guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
		else {
			return true
		}

		let currentModificationDate = resourceValues.contentModificationDate
		let currentFileSize = resourceValues.fileSize.map { Int64($0) }

		// Compare modification dates (primary check)
		if let original = originalModificationDate,
		   let current = currentModificationDate {
			if current != original {
				return true
			}
		}

		// Compare file sizes (secondary check)
		if let original = originalFileSize,
		   let current = currentFileSize {
			if current != original {
				return true
			}
		}

		return false
	}
}
