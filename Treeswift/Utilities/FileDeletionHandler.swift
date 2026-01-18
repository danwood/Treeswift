//
//  FileDeletionHandler.swift
//  Treeswift
//
//  File deletion and restoration utility for undo/redo support
//

import Foundation

// Extension to enable printing to stderr
extension FileHandle: TextOutputStream {
	public func write(_ string: String) {
		if let data = string.data(using: .utf8) {
			write(data)
		}
	}
}

enum FileDeletionHandler {
	/**
	 Moves a file to the trash.

	 Returns true if successful, false otherwise.
	 Logs to stderr with the file path.
	 On error, logs the error but doesn't throw (allows operation to continue).
	 */
	static func moveToTrash(filePath: String) -> Bool {
		let fileURL = URL(fileURLWithPath: filePath)
		let fileManager = FileManager.default

		guard fileManager.fileExists(atPath: filePath) else {
			var stderr = FileHandle.standardError
			print("Warning: File does not exist, cannot delete: \(filePath)", to: &stderr)
			return false
		}

		do {
			var resultingURL: NSURL?
			try fileManager.trashItem(at: fileURL, resultingItemURL: &resultingURL)

			var stderr = FileHandle.standardError
			print("Deleted file: \(filePath)", to: &stderr)
			return true

		} catch {
			var stderr = FileHandle.standardError
			print("Error deleting file \(filePath): \(error.localizedDescription)", to: &stderr)
			return false
		}
	}

	/**
	 Restores a file by writing its contents to the original path.

	 Creates parent directories if needed.
	 Returns true if successful, false otherwise.
	 Logs to stderr with the file path.
	 On error, logs the error but doesn't throw (allows operation to continue).
	 */
	static func restoreFile(filePath: String, contents: String) -> Bool {
		let fileURL = URL(fileURLWithPath: filePath)
		let fileManager = FileManager.default

		do {
			// Create parent directory if needed
			let parentDirectory = fileURL.deletingLastPathComponent()
			if !fileManager.fileExists(atPath: parentDirectory.path) {
				try fileManager.createDirectory(
					at: parentDirectory,
					withIntermediateDirectories: true,
					attributes: nil
				)
			}

			// Write file contents
			try contents.write(to: fileURL, atomically: true, encoding: .utf8)

			var stderr = FileHandle.standardError
			print("Restored file: \(filePath)", to: &stderr)
			return true

		} catch {
			var stderr = FileHandle.standardError
			print("Error restoring file \(filePath): \(error.localizedDescription)", to: &stderr)
			return false
		}
	}
}
