import Foundation

/**
 Centralized logging for source code modifications.

 When enabled, logs each modification in a Periphery-like format to stderr,
 e.g. `/Path/To/File.swift:10:25: Deleted`.
 The `isEnabled` flag is set from the configuration's `shouldLogToConsole` property
 at scan start and read during modifications — always on the main thread in practice.
 */
enum ModificationLogger {
	/// Controls whether modification actions are logged to the console.
	/// Set this from the configuration's `shouldLogToConsole` when a scan starts.
	nonisolated(unsafe) static var isEnabled: Bool = false

	/**
	 Logs a modification action for a range of lines in a file.

	 Format: `/Path/To/File.swift:startLine:endLine: action`
	 When startLine equals endLine, only one line number is shown.
	 */
	static func log(filePath: String, startLine: Int, endLine: Int, action: String) {
		guard isEnabled else { return }
		let lineRange = startLine == endLine ? "\(startLine)" : "\(startLine):\(endLine)"
		"\(filePath):\(lineRange): \(action)".logToConsole()
	}

	/**
	 Logs a file-level action (e.g. file deletion) with no line range.

	 Format: `/Path/To/File.swift: action`
	 */
	static func log(filePath: String, action: String) {
		guard isEnabled else { return }
		"\(filePath): \(action)".logToConsole()
	}

	/**
	 A pending log entry collected during batch operations.

	 Entries are collected during the per-operation loop, then merged and emitted
	 after post-processing (orphan comment removal, blank line collapse) so that
	 contiguous deletion ranges appear as a single log entry.
	 */
	struct PendingEntry {
		var startLine: Int
		var endLine: Int
		let action: String
		// For deletions, tracks the original sub-ranges before merging
		var subRanges: [(start: Int, end: Int)]

		init(startLine: Int, endLine: Int, action: String) {
			self.startLine = startLine
			self.endLine = endLine
			self.action = action
			subRanges = [(startLine, endLine)]
		}

		/// Whether this entry represents a line deletion (as opposed to an in-place edit).
		var isDeletion: Bool {
			action == "Deleted" || action.hasPrefix("Deleted import") || action.hasPrefix("removed `periphery:ignore`")
		}
	}

	/**
	 Merges contiguous deletion entries and emits all collected log entries.

	 Deletion entries whose ranges are adjacent or overlapping are merged into a single
	 entry. When multiple sub-ranges are merged, the action shows all original ranges,
	 e.g. `Deleted 60:68,69:76,77:82`. Non-deletion entries (access control changes,
	 inline enum case edits) are emitted individually without merging.
	 */
	static func emitPendingEntries(_ entries: [PendingEntry], filePath: String) {
		guard isEnabled, !entries.isEmpty else { return }

		// Sort entries by startLine ascending for merging
		let sorted = entries.sorted { $0.startLine < $1.startLine }

		var merged: [PendingEntry] = []
		for entry in sorted {
			if entry.isDeletion,
			   var last = merged.last,
			   last.isDeletion,
			   entry.startLine <= last.endLine + 1 {
				// Extend the previous deletion range and collect sub-ranges
				last.endLine = max(last.endLine, entry.endLine)
				last.subRanges.append(contentsOf: entry.subRanges)
				merged[merged.count - 1] = last
			} else {
				merged.append(entry)
			}
		}

		for entry in merged.reversed() {
			if entry.isDeletion, entry.subRanges.count > 1 {
				// Multiple sub-ranges were merged — show them all
				let rangeDescriptions = entry.subRanges
					.sorted { $0.start < $1.start }
					.map { $0.start == $0.end ? "\($0.start)" : "\($0.start):\($0.end)" }
					.joined(separator: ",")
				log(
					filePath: filePath,
					startLine: entry.startLine,
					endLine: entry.endLine,
					action: "Deleted \(rangeDescriptions)"
				)
			} else {
				log(filePath: filePath, startLine: entry.startLine, endLine: entry.endLine, action: entry.action)
			}
		}
	}
}
