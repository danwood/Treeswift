import Foundation
import SourceGraph
import SystemPackage

/**
 Shared utilities for modifying source code (non-deletion operations).

 Provides pure functions that work on file contents and return before/after state
 for undo support. Callers are responsible for source graph updates and undo registration.
 */
struct CodeModificationHelper {
	/**
	 Result of a code modification operation.

	 Contains the original and modified file contents, along with metadata about
	 what changed and where. Used for undo/redo support and line number adjustments.
	 */
	struct ModificationResult {
		let filePath: String
		let originalContents: String
		let modifiedContents: String
		let linesRemoved: Int // 0 for replacements, >0 for deletions
		let startLine: Int
		let endLine: Int

		/**
		 Finds declarations affected by this modification and adjusts their line numbers.

		 Returns USRs of adjusted declarations for undo tracking.
		 Only performs adjustment if lines were actually removed.
		 */
		func adjustSourceGraph(_ sourceGraph: SourceGraph) -> [String] {
			guard linesRemoved > 0 else { return [] }

			return SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: sourceGraph,
				filePath: filePath,
				afterLine: endLine,
				lineDelta: -linesRemoved
			)
		}
	}

	// MARK: - Access Control Modifications

	/**
	 Removes redundant public keyword from a declaration.

	 Uses regex to match "public" followed by any whitespace and replaces with empty string.
	 This makes the declaration internal (Swift's default accessibility).

	 Note: This method is deprecated in favor of fixAccessControl(.removePublic).
	 Kept temporarily for backward compatibility during refactoring.
	 */
	static func removeRedundantPublic(
		declaration: Declaration,
		location: Location
	) -> Result<ModificationResult, Error> {
		let filePath = location.file.path.string
		guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(CodeModificationError.cannotReadFile(filePath))
		}

		// Verify structural confirmation that 'public' modifier exists
		guard declaration.modifiers.contains("public") else {
			return .failure(CodeModificationError.patternNotFound("public"))
		}

		var lines = fileContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(CodeModificationError.invalidLineRange(location.line, lines.count))
		}

		let lineIndex = location.line - 1
		let originalLine = lines[lineIndex]

		// Match "public" followed by any whitespace (space, newline, tab, etc.)
		let pattern = #"public\s+"#
		guard let regex = try? NSRegularExpression(pattern: pattern) else {
			return .failure(CodeModificationError.patternNotFound("public"))
		}

		let range = NSRange(originalLine.startIndex..., in: originalLine)
		let newLine = regex.stringByReplacingMatches(
			in: originalLine,
			range: range,
			withTemplate: ""
		)
		lines[lineIndex] = newLine

		let modifiedContents = lines.joined(separator: "\n")

		// Write back to file
		do {
			try modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(CodeModificationError.cannotWriteFile(filePath))
		}

		return .success(ModificationResult(
			filePath: filePath,
			originalContents: fileContents,
			modifiedContents: modifiedContents,
			linesRemoved: 0, // Replacement, not deletion
			startLine: location.line,
			endLine: location.line
		))
	}

	/**
	 Removes superfluous periphery:ignore comment from source code.

	 Scans backwards from the declaration line to find the ignore directive comment.
	 Handles all Periphery ignore formats (basic, with explanation, range-based).
	 Optionally removes trailing blank line after the comment.
	 */
	static func removeSuperfluousIgnoreComment(
		declaration: Declaration,
		location: Location
	) -> Result<ModificationResult, Error> {
		let filePath = location.file.path.string
		guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(CodeModificationError.cannotReadFile(filePath))
		}

		let lines = fileContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(CodeModificationError.invalidLineRange(location.line, lines.count))
		}

		// Use CommentScanner to find the periphery:ignore comment
		guard let ignoreLineNumber = CommentScanner.findCommentContaining(
			pattern: "periphery:ignore",
			in: lines,
			backwardFrom: location.line,
			maxDistance: 10
		) else {
			return .failure(CodeModificationError.patternNotFound("periphery:ignore"))
		}

		// Determine deletion range
		let startLine = ignoreLineNumber
		var endLine = ignoreLineNumber

		// Check if there's a trailing blank line to remove
		let nextLineIndex = ignoreLineNumber // (ignoreLineNumber is 1-based, so this gives us the line after)
		if nextLineIndex < lines.count {
			let nextLine = lines[nextLineIndex].trimmingCharacters(in: .whitespaces)
			if nextLine.isEmpty {
				endLine = ignoreLineNumber + 1
			}
		}

		// Remove the line(s)
		var modifiedLines = lines
		let startIndex = startLine - 1
		let endIndex = endLine - 1
		modifiedLines.removeSubrange(startIndex ... endIndex)

		let modifiedContents = modifiedLines.joined(separator: "\n")

		// Write back to file
		do {
			try modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(CodeModificationError.cannotWriteFile(filePath))
		}

		let linesRemoved = endLine - startLine + 1

		return .success(ModificationResult(
			filePath: filePath,
			originalContents: fileContents,
			modifiedContents: modifiedContents,
			linesRemoved: linesRemoved,
			startLine: startLine,
			endLine: endLine
		))
	}
}
