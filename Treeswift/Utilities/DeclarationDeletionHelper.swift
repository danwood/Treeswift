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
		// Extract just the attribute name (before any parentheses)
		let attributePatterns = attributes.map { attr -> String in
			let attrDesc = attr.description
			let attrName = attrDesc.components(separatedBy: "(").first ?? attrDesc
			return "@\(attrName)"
		}

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

		// Then look backwards for documentation comments
		// Documentation comments can have one blank line between them and the declaration
		var foundBlankLine = false
		var lastCommentLine: Int?

		while checkLine >= 1 {
			let lineIndex = checkLine - 1
			guard lineIndex >= 0 && lineIndex < lines.count else { break }

			let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)

			// Handle blank lines
			if line.isEmpty {
				if foundBlankLine {
					// Second blank line - stop here
					break
				}
				foundBlankLine = true
				checkLine -= 1
				continue
			}

			// Stop if we hit another declaration
			if isDeclarationLine(line) {
				break
			}

			// Check if this is a comment line
			let isComment = line.hasPrefix("//") || line.hasPrefix("/*") || line.hasPrefix("*") || line.hasPrefix("/**")

			if isComment {
				// Include this comment
				startLine = checkLine
				lastCommentLine = checkLine
				checkLine -= 1
				// Reset blank line counter when we find a comment
				foundBlankLine = false
			} else {
				// Not a comment and not blank - stop here
				break
			}
		}

		// If we found a blank line but then found comments before it,
		// make sure we don't include the blank line in the deletion
		if foundBlankLine, lastCommentLine != nil {
			// The startLine is already set correctly to the comment line
			// No adjustment needed
		}

		return startLine
	}

	/**
	 Find the insertion point for periphery:ignore comments.

	 Similar to findDeletionStartLine, but stops BEFORE documentation comments.
	 This ensures the ignore directive appears above docs, preventing linter errors.

	 Includes:
	 - Attribute lines containing @AttributeName
	 - Multi-line attribute continuations
	 Excludes:
	 - Documentation comments (triple-slash and multi-line doc comments)
	 - Regular comments
	 */
	static func findIgnoreCommentInsertionLine(
		lines: [String],
		declarationLine: Int,
		attributes: Set<DeclarationAttribute>
	) -> Int {
		guard declarationLine > 1 else { return declarationLine }

		var startLine = declarationLine
		var checkLine = declarationLine - 1

		// If no attributes, return declaration line (insert right before it)
		guard !attributes.isEmpty else {
			return startLine
		}

		// Build patterns to search for (e.g., @State, @FetchRequest, etc.)
		let attributePatterns = attributes.map { attr -> String in
			let attrName = attr.description.components(separatedBy: "(").first ?? attr.description
			return "@\(attrName)"
		}

		// Track lines that are part of attributes
		var attributeLines: [Int] = []
		var tempCheckLine = checkLine
		var inMultiLineAttribute = false

		// Look backwards for attribute lines ONLY (not comments)
		var foundAttributeYet = false
		while tempCheckLine >= 1 {
			let lineIndex = tempCheckLine - 1
			guard lineIndex >= 0 && lineIndex < lines.count else { break }
			let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)

			// Stop at blank lines
			if line.isEmpty {
				break
			}

			// Stop at comment lines (this is the key difference from findDeletionStartLine)
			if line.hasPrefix("//") || line.hasPrefix("/*") || line.hasPrefix("*") || line.hasPrefix("/**") {
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
				attributeLines.insert(tempCheckLine, at: 0)
				if line.contains(")"), !line.contains("(") {
					inMultiLineAttribute = true
				} else if line.contains("(") {
					inMultiLineAttribute = false
				}
				tempCheckLine -= 1
			} else {
				break
			}
		}

		// Use earliest attribute line if found, otherwise use declaration line
		if !attributeLines.isEmpty {
			startLine = attributeLines.first!
		}

		return startLine
	}

	/**
	 Find the last line to delete (including trailing blank lines).

	 If the deleted declaration has a blank line above AND below, remove the trailing blank.
	 This prevents accumulation of extra whitespace.
	 */
	static func findDeletionEndLine(
		lines: [String],
		declarationLine: Int,
		declarationEndLine: Int
	) -> Int {
		var endLine = declarationEndLine

		// Check if there's a blank line before the declaration
		let hasBlankAbove: Bool = {
			guard declarationLine > 1 else { return false }
			let lineIndex = declarationLine - 2
			guard lineIndex >= 0, lineIndex < lines.count else { return false }
			return lines[lineIndex].trimmingCharacters(in: .whitespaces).isEmpty
		}()

		// Look for blank lines after the declaration
		var currentLine = declarationEndLine
		var foundBlankBelow = false

		while currentLine < lines.count {
			let line = lines[currentLine]
			if line.trimmingCharacters(in: .whitespaces).isEmpty {
				foundBlankBelow = true
				endLine = currentLine + 1
				currentLine += 1
			} else {
				break
			}
		}

		// If blank above AND below, include the trailing blank in deletion
		if hasBlankAbove, foundBlankBelow {
			return endLine
		}

		// Otherwise, don't include trailing blanks (preserve spacing)
		return declarationEndLine
	}
}
