import Foundation
import SourceGraph
import SystemPackage

// Helper for intelligently deleting declarations from source files
struct DeclarationDeletionHelper {
	/**
	 Detects if a line contains a complete declaration.

	 A declaration line contains keywords like var, let, func, struct, etc.
	 Distinguishes between attribute lines (@State var foo) which ARE declarations,
	 and pure attribute lines (@FetchRequest(...)) which are NOT declarations.
	 */
	private static func isDeclarationLine(_ line: String) -> Bool {
		let trimmed = line.trimmingCharacters(in: .whitespaces)

		// Declaration keywords that indicate a complete declaration
		let declarationKeywords = [
			"var ", "let ", "func ",
			"struct ", "class ", "enum ", "protocol ", "actor ",
			"init(", "init ", "deinit ", "subscript ",
			"typealias ", "associatedtype "
		]

		// Check if line contains a declaration keyword
		for keyword in declarationKeywords {
			if trimmed.contains(keyword) {
				// Make sure it's not just an attribute line like "@State private var"
				// If the line starts with @, check if there's a keyword AFTER the @Attribute
				if trimmed.hasPrefix("@") {
					// This might be "@State var foo" which IS a declaration
					// Find the attribute name and check what comes after
					if let spaceIndex = trimmed.firstIndex(of: " ") {
						let afterAttribute = String(trimmed[trimmed.index(after: spaceIndex)...])
						// Check if keyword appears after the attribute
						return declarationKeywords.contains { afterAttribute.contains($0) }
					}
					return false
				}
				return true
			}
		}
		return false
	}

	/**
	 Find the first line to delete by looking backwards from the declaration.

	 Uses declaration metadata to know which attributes to look for, then scans
	 source to find where they appear (handles both start-of-line and mid-line).

	 Includes:
	 - Attribute lines containing @AttributeName (e.g., @MainActor, @FetchRequest, private @Published)
	 - Multi-line attribute continuations
	 - Adjacent comment lines (no blank lines between them and the declaration)
	 Stops at blank lines to preserve spacing between declarations.
	 */
	static func findDeletionStartLine(
		lines: [String],
		declarationLine: Int,
		attributes: Set<DeclarationAttribute>
	) -> Int {
		guard declarationLine > 1 else { return declarationLine }

		var startLine = declarationLine
		var checkLine = declarationLine - 1

		// If no attributes, skip attribute search
		guard !attributes.isEmpty else {
			// Jump straight to comment search below
			return startLine
		}

		// Build patterns to search for (e.g., @State, @FetchRequest, etc.)
		let attributePatterns = attributes.map { "@\($0)" }

		// Track lines that are part of attributes
		var attributeLines: [Int] = []
		var tempCheckLine = checkLine
		var inMultiLineAttribute = false

		// Look backwards for attribute lines
		var foundAttributeYet = false
		while tempCheckLine >= 1 {
			let lineIndex = tempCheckLine - 1
			guard lineIndex >= 0 && lineIndex < lines.count else { break }
			let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)

			// Stop at blank lines
			if line.isEmpty {
				break
			}

			// Stop if we hit another declaration
			if isDeclarationLine(line) {
				break
			}

			// Check if this line contains any of our attribute patterns
			let containsAttribute = attributePatterns.contains { pattern in
				line.contains(pattern)
			}

			if containsAttribute {
				// Check if it's a complete declaration (another var/func with this attribute)
				let declarationKeywords = [
					"var ",
					"let ",
					"func ",
					"class ",
					"struct ",
					"enum ",
					"protocol ",
					"actor ",
					"init ",
					"deinit ",
					"subscript "
				]
				let isDeclaration = declarationKeywords.contains { line.contains($0) }

				if isDeclaration {
					break
				} else {
					attributeLines.insert(tempCheckLine, at: 0)
					foundAttributeYet = true
					// Check if this starts a multi-line attribute
					inMultiLineAttribute = line.contains("(") && !line.contains(")")
					tempCheckLine -= 1
				}
			} else if inMultiLineAttribute ||
				(!foundAttributeYet && (line.contains(")") || line.contains(":") || line.contains(","))) {
				// Either: we're in a known multi-line attribute, OR
				// we haven't found the attribute yet but this looks like it could be part of one
				attributeLines.insert(tempCheckLine, at: 0)
				// Check if this closes a paren (might complete the search area)
				if line.contains(")"), !line.contains("(") {
					// This line has a closing paren, we're likely exiting an attribute
					inMultiLineAttribute = true
				} else if line.contains("(") {
					inMultiLineAttribute = false
				}
				tempCheckLine -= 1
			} else {
				break
			}
		}

		// Update startLine if we found attributes
		if !attributeLines.isEmpty {
			startLine = attributeLines.first!
			checkLine = attributeLines.first! - 1
		}

		// Then look backwards for adjacent comment lines (no blank lines between)
		while checkLine >= 1 {
			let lineIndex = checkLine - 1
			guard lineIndex >= 0 && lineIndex < lines.count else { break }

			let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)

			// Stop at blank lines - we don't want to delete spacing
			if line.isEmpty {
				break
			}

			// Stop if we hit another declaration
			if isDeclarationLine(line) {
				break
			}

			// Include comment lines
			if line.hasPrefix("//") || line.hasPrefix("/*") || line.hasPrefix("*") {
				startLine = checkLine
				checkLine -= 1
			} else {
				break
			}
		}

		return startLine
	}

	// Find the last line to delete (including trailing blank lines)
	static func findDeletionEndLine(
		lines: [String],
		declarationEndLine: Int
	) -> Int {
		var endLine = declarationEndLine
		var currentLine = declarationEndLine

		while currentLine < lines.count {
			let line = lines[currentLine]
			if line.trimmingCharacters(in: .whitespaces).isEmpty {
				endLine = currentLine + 1
				currentLine += 1
			} else {
				break
			}
		}

		return endLine
	}
}
