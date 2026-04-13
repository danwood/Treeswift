import Foundation

/**
 Utilities for finding comment lines in source code.

 Provides methods for scanning backward from a given line to find
 comment blocks, specific comment patterns, and periphery directives.
 */
struct CommentScanner {
	/**
	 Finds a line containing a specific pattern in comments.

	 Scans backward from startLine looking for a comment line that contains
	 the given pattern. Returns the 1-based line number, or nil if not found.

	 Stops scanning at blank lines or non-comment lines.
	 */
	static func findCommentContaining(
		pattern: String,
		in lines: [String],
		backwardFrom startLine: Int,
		maxDistance: Int = 10
	) -> Int? {
		var checkLine = startLine - 1
		let searchLimit = max(1, startLine - maxDistance)

		while checkLine >= searchLimit {
			let lineIndex = checkLine - 1
			guard lineIndex >= 0 && lineIndex < lines.count else { break }

			let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)

			// Stop at blank lines or non-comments
			if line.isEmpty || !line.hasPrefix("//") {
				break
			}

			// Check if this line contains the pattern
			if line.contains(pattern) {
				return checkLine
			}

			checkLine -= 1
		}

		return nil
	}
}
