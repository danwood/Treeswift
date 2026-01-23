import Foundation
import SourceGraph
import SystemPackage

/**
 Utilities for adjusting line numbers in SourceGraph after file modifications.

 Handles updating declaration locations when lines are added or removed from source files.
 Supports both forward adjustments (during modification) and reverse adjustments (for undo).
 */
struct SourceGraphLineAdjuster {
	/**
	 Adjusts line numbers and returns affected declaration USRs.

	 This is the primary method all code should use. Combines adjustment
	 and USR tracking in one operation.

	 Use negative lineDelta for deletions (lines removed), positive for insertions (lines added).
	 */
	static func adjustAndTrack(
		sourceGraph: SourceGraph,
		filePath: String,
		afterLine: Int,
		lineDelta: Int // negative for deletions, positive for insertions
	) -> [String] {
		var adjustedUSRs: [String] = []

		for declaration in sourceGraph.allDeclarations {
			// Only adjust declarations in the same file
			guard declaration.location.file.path.string == filePath else { continue }

			// Only adjust declarations after the modification point
			guard declaration.location.line > afterLine else { continue }

			// Apply adjustment to line numbers
			let newLine = declaration.location.line + lineDelta
			let newEndLine = declaration.location.endLine.map { $0 + lineDelta }

			declaration.location = Location(
				file: declaration.location.file,
				line: newLine,
				column: declaration.location.column,
				endLine: newEndLine,
				endColumn: declaration.location.endColumn
			)

			// Track which declarations were adjusted
			if let usr = declaration.usrs.first {
				adjustedUSRs.append(usr)
			}
		}

		return adjustedUSRs
	}

	/**
	 Reverses a previous line number adjustment.

	 Used during undo operations to restore declarations to their original line numbers.
	 Only adjusts declarations whose USRs are in the provided tracking list.
	 */
	static func reverseLineAdjustment(
		sourceGraph: SourceGraph,
		filePath: String,
		usrs: [String],
		adjustment: Int // The original adjustment (will be reversed)
	) {
		for declaration in sourceGraph.allDeclarations {
			// Only adjust declarations in the same file
			guard declaration.location.file.path.string == filePath else { continue }

			// Only adjust declarations that were previously modified
			guard let declUSR = declaration.usrs.first else { continue }
			guard usrs.contains(declUSR) else { continue }

			// Reverse the adjustment
			let newLine = declaration.location.line - adjustment
			let newEndLine = declaration.location.endLine.map { $0 - adjustment }

			declaration.location = Location(
				file: declaration.location.file,
				line: newLine,
				column: declaration.location.column,
				endLine: newEndLine,
				endColumn: declaration.location.endColumn
			)
		}
	}
}
