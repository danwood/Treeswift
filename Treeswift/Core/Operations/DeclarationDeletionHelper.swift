import Foundation
import SourceGraph
import SystemPackage

// Helper for intelligently deleting declarations from source files
struct DeclarationDeletionHelper {
	/**
	 Handles deletion of an enum case when multiple cases are on the same line.

	 Returns modified file contents if successful, nil if the case should use normal deletion logic.
	 Handles patterns like: "case foo, bar, baz" or "enum Foo { case info, celebration }"
	 */
	static func handleInlineEnumCaseDeletion(
		lines: [String],
		declarationLine: Int,
		caseName: String
	) -> [String]? {
		guard declarationLine > 0, declarationLine <= lines.count else { return nil }

		let lineIndex = declarationLine - 1
		let line = lines[lineIndex]
		let trimmed = line.trimmingCharacters(in: .whitespaces)

		// Check if this line contains "case" keyword and multiple comma-separated cases
		guard trimmed.contains("case "), trimmed.contains(",") else { return nil }

		// Extract the case list portion
		// Handle both "case foo, bar" and "enum X { case foo, bar }"
		guard let caseKeywordRange = trimmed.range(of: "case ") else { return nil }
		let afterCase = String(trimmed[caseKeywordRange.upperBound...])

		// Find where the case list ends (look for closing brace, comment, or end of line)
		// This handles patterns like "case foo, bar }" or "case foo, bar // comment"
		var caseListEnd = afterCase.endIndex
		var afterCaseList = ""

		if let braceIndex = afterCase.firstIndex(of: "}") {
			caseListEnd = braceIndex
			afterCaseList = String(afterCase[braceIndex...])
		} else if let commentIndex = afterCase.range(of: "//")?.lowerBound {
			caseListEnd = commentIndex
			afterCaseList = String(afterCase[commentIndex...])
		}

		let caseListString = String(afterCase[..<caseListEnd]).trimmingCharacters(in: .whitespaces)

		// Split by comma to get individual cases
		var cases = caseListString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

		// Find and remove the matching case
		// The case name might have associated values or raw values, so we check if it starts with the case name
		var foundIndex: Int?
		for (index, caseItem) in cases.enumerated() {
			// Extract just the case name (before any '(' or '=' or whitespace)
			let caseItemName = caseItem.components(separatedBy: CharacterSet(charactersIn: "(= \t")).first ?? caseItem
			if caseItemName == caseName {
				foundIndex = index
				break
			}
		}

		guard let indexToRemove = foundIndex else { return nil }

		// If this is the only case on the line, use normal deletion
		if cases.count == 1 {
			return nil
		}

		// Remove the case from the array
		cases.remove(at: indexToRemove)

		// Reconstruct the line
		let beforeCase = String(trimmed[..<caseKeywordRange.lowerBound])
		let newCaseList = cases.joined(separator: ", ")

		// Preserve original indentation and include any trailing content (like closing brace)
		let leadingWhitespace = String(line.prefix(while: { $0.isWhitespace }))
		let newLine = leadingWhitespace + beforeCase + "case " + newCaseList +
			(afterCaseList.isEmpty ? "" : " \(afterCaseList)")

		// Update the line in the array
		var modifiedLines = lines
		modifiedLines[lineIndex] = newLine

		return modifiedLines
	}

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

		// Only search for attributes if the declaration has any
		if !attributes.isEmpty {
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

				// Stop at preprocessor directives (#if, #endif, #else, etc.)
				if line.hasPrefix("#") {
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
		}

		// Then look backwards for documentation comments
		// Doc comments directly above declarations (no blank lines) are removed
		// Section markers (MARK, TODO, FIXME) are preserved
		var lastCommentLine: Int?
		var inBlockComment = false // Track if we're in a /* ... */ block

		while checkLine >= 1 {
			let lineIndex = checkLine - 1
			guard lineIndex >= 0 && lineIndex < lines.count else { break }

			let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)

			// Handle blank lines
			if line.isEmpty {
				if lastCommentLine != nil {
					// Found blank line after seeing comments - stop here
					break
				}
				checkLine -= 1
				continue
			}

			// Stop at preprocessor directives (#if, #endif, #else, etc.)
			if line.hasPrefix("#") {
				break
			}

			// Stop if we hit another declaration
			if isDeclarationLine(line) {
				break
			}

			// Check for section markers (MARK, TODO, FIXME) - these are NOT part of declarations
			if line.hasPrefix("// MARK:") ||
				line.hasPrefix("// TODO:") ||
				line.hasPrefix("// FIXME:") {
				break
			}

			// Check comment type
			let isDocComment = line.hasPrefix("///") || line.hasPrefix("/**") || line.hasPrefix("*/")
			let isBlockCommentLine = line.hasPrefix("*") && !line.hasPrefix("*/")
			let isRegularComment = line.hasPrefix("//") && !line.hasPrefix("///")
			let isBlockCommentStart = line.hasPrefix("/*") && !line.hasPrefix("/**")

			if isDocComment {
				// Doc comments are always part of the declaration
				startLine = checkLine
				lastCommentLine = checkLine
				checkLine -= 1

				// Track block comment state
				if line.hasPrefix("/**"), !line.contains("*/") {
					inBlockComment = true
				}
				if line.hasPrefix("*/") {
					inBlockComment = true // We're scanning backward, so */ comes before /*
				}

			} else if isBlockCommentLine, inBlockComment {
				// Middle line of a block comment (starts with * but not */)
				startLine = checkLine
				lastCommentLine = checkLine
				checkLine -= 1

			} else if isBlockCommentStart {
				// Found start of block comment (scanning backward, so this is the opening of the comment)
				startLine = checkLine
				lastCommentLine = checkLine
				inBlockComment = false
				checkLine -= 1

			} else if isRegularComment {
				// Regular comments only included if directly adjacent (will break on blank line above)
				startLine = checkLine
				lastCommentLine = checkLine
				checkLine -= 1

			} else {
				// Not a comment and not blank - stop here
				break
			}
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
		let checkLine = declarationLine - 1

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

			// Stop at preprocessor directives (#if, #endif, #else, etc.)
			if line.hasPrefix("#") {
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
	 Find the last line to delete (including trailing blank lines and empty #if blocks).

	 If the deleted declaration has a blank line above AND below, remove the trailing blank.
	 This prevents accumulation of extra whitespace.

	 Also checks if the declaration is inside a #if block that would become empty after deletion.
	 If so, includes the entire #if/#endif block in the deletion range.
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

	/**
	 Removes orphaned MARK/TODO/FIXME comments that have no code between them and the next
	 section marker, end of file, or closing brace.

	 After batch deletion of all declarations under a MARK section, the MARK comment itself
	 would remain as a stale artifact. This method scans the lines and removes any section
	 marker comments that have no meaningful code between them and the next boundary.
	 */
	static func removeOrphanedSectionMarkers(from lines: [String]) -> [String] {
		var result = lines
		var index = 0

		while index < result.count {
			let trimmed = result[index].trimmingCharacters(in: .whitespaces)

			// Check if this line is a section marker
			guard trimmed.hasPrefix("// MARK:") ||
				trimmed.hasPrefix("// TODO:") ||
				trimmed.hasPrefix("// FIXME:") else {
				index += 1
				continue
			}

			// Found a section marker - check if there's any code between here and the next boundary
			let hasCode = sectionHasCode(in: result, afterIndex: index)

			if !hasCode {
				// Remove the marker line and any immediately following blank line
				result.remove(at: index)
				if index < result.count,
				   result[index].trimmingCharacters(in: .whitespaces).isEmpty {
					result.remove(at: index)
				}
				// Don't increment index - check the new line at this position
			} else {
				index += 1
			}
		}

		return result
	}

	/**
	 Collapses runs of two or more consecutive blank lines down to a single blank line.

	 After batch deletion of multiple adjacent declarations, the blank lines that separated
	 them remain, creating unsightly gaps. This pass normalizes whitespace.
	 */
	static func collapseConsecutiveBlankLines(in lines: [String]) -> [String] {
		var result: [String] = []
		var lastWasBlank = false

		for line in lines {
			let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
			if isBlank, lastWasBlank {
				continue
			}
			result.append(line)
			lastWasBlank = isBlank
		}

		return result
	}

	/**
	 Removes empty containers (extensions, classes, structs, enums, actors) left behind
	 after batch deletion of their contents.

	 Periphery folds extension members into the extended type's declaration graph, so
	 `findHighestEmptyAncestor` cannot detect empty extensions. This post-processing pass
	 scans the source text for container declarations whose body contains only whitespace
	 and comments, and removes them along with any immediately preceding comments.
	 */
	static func removeEmptyContainers(from lines: [String]) -> [String] {
		var result = lines
		var index = 0

		let containerKeywords = ["extension ", "class ", "struct ", "enum ", "actor "]

		while index < result.count {
			let trimmed = result[index].trimmingCharacters(in: .whitespaces)

			// Skip comment lines to avoid false matches
			guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("/*"), !trimmed.hasPrefix("*") else {
				index += 1
				continue
			}

			// Check if this line starts a container declaration
			let isContainer = containerKeywords.contains { keyword in
				trimmed.hasPrefix(keyword) || trimmed.contains(" \(keyword)")
			}

			guard isContainer, trimmed.contains("{") else {
				index += 1
				continue
			}

			// If the opening brace is on this line, find the matching closing brace
			let openBraceIndex = index
			guard let closeBraceIndex = findMatchingCloseBrace(in: result, from: openBraceIndex) else {
				index += 1
				continue
			}

			// Check if the body between braces contains only whitespace and comments.
			// When openBraceIndex == closeBraceIndex the opening and closing braces
			// are on the same line (e.g. `extension Foo {}`). In that case, check
			// whether the text between the braces on that single line is blank.
			let bodyIsEmpty: Bool
			if openBraceIndex == closeBraceIndex {
				let line = result[openBraceIndex]
				if let openIdx = line.firstIndex(of: "{"),
				   let closeIdx = line.lastIndex(of: "}"),
				   openIdx < closeIdx {
					let between = line[line.index(after: openIdx) ..< closeIdx]
					bodyIsEmpty = between.allSatisfy(\.isWhitespace)
				} else {
					bodyIsEmpty = false
				}
			} else {
				bodyIsEmpty = (openBraceIndex + 1 ..< closeBraceIndex).allSatisfy { lineIdx in
					let bodyTrimmed = result[lineIdx].trimmingCharacters(in: .whitespaces)
					return bodyTrimmed.isEmpty ||
						bodyTrimmed.hasPrefix("//") ||
						bodyTrimmed.hasPrefix("/*") ||
						bodyTrimmed.hasPrefix("*") ||
						bodyTrimmed.hasPrefix("*/")
				}
			}

			guard bodyIsEmpty else {
				index += 1
				continue
			}

			// Scan backward to include preceding attributes, comments, and blank lines
			// (mirrors the logic in findDeletionStartLine for regular declarations).
			// Section markers (MARK, TODO, FIXME) are NOT consumed here — they are
			// handled separately by removeOrphanedSectionMarkers, which checks whether
			// the section still has code below the deleted container.
			var startIndex = openBraceIndex
			while startIndex > 0 {
				let prevTrimmed = result[startIndex - 1].trimmingCharacters(in: .whitespaces)

				// Stop at section markers — these head sections that may contain other code
				if prevTrimmed.hasPrefix("// MARK:") ||
					prevTrimmed.hasPrefix("// TODO:") ||
					prevTrimmed.hasPrefix("// FIXME:") {
					break
				}

				if prevTrimmed.hasPrefix("@") ||
					prevTrimmed.hasPrefix("//") ||
					prevTrimmed.hasPrefix("/*") ||
					prevTrimmed.hasPrefix("*") ||
					prevTrimmed.hasPrefix("*/") ||
					prevTrimmed.isEmpty {
					startIndex -= 1
				} else {
					break
				}
			}

			// Also include trailing blank line after the closing brace if present
			var endIndex = closeBraceIndex
			if endIndex + 1 < result.count,
			   result[endIndex + 1].trimmingCharacters(in: .whitespaces).isEmpty {
				endIndex += 1
			}

			result.removeSubrange(startIndex ... endIndex)
			// Don't increment index — check the new line at this position
		}

		return result
	}

	/**
	 Finds the matching closing brace for a line containing an opening brace.

	 Returns the index of the line containing the matching `}`, tracking brace depth.
	 */
	private static func findMatchingCloseBrace(in lines: [String], from startIndex: Int) -> Int? {
		var depth = 0
		for idx in startIndex ..< lines.count {
			let line = lines[idx]
			for char in line {
				if char == "{" { depth += 1 }
				if char == "}" { depth -= 1 }
			}
			if depth == 0 {
				return idx
			}
		}
		return nil
	}

	/**
	 Checks whether a MARK/TODO/FIXME section contains any meaningful code lines.

	 Scans forward from the line after the section marker until hitting another section marker,
	 end of file, or a closing brace at the same or lower indentation level.
	 */
	private static func sectionHasCode(in lines: [String], afterIndex markerIndex: Int) -> Bool {
		var checkIndex = markerIndex + 1

		while checkIndex < lines.count {
			let trimmed = lines[checkIndex].trimmingCharacters(in: .whitespaces)

			// Skip blank lines
			if trimmed.isEmpty {
				checkIndex += 1
				continue
			}

			// Another section marker means end of this section
			if trimmed.hasPrefix("// MARK:") ||
				trimmed.hasPrefix("// TODO:") ||
				trimmed.hasPrefix("// FIXME:") {
				return false
			}

			// A closing brace at top-level indentation means end of the containing scope
			if trimmed == "}" {
				return false
			}

			// Any other non-empty, non-comment content counts as code
			if !trimmed.hasPrefix("//"),
			   !trimmed.hasPrefix("/*"),
			   !trimmed.hasPrefix("*"),
			   !trimmed.hasPrefix("*/") {
				return true
			}

			// Regular comments don't count as code
			checkIndex += 1
		}

		// Reached end of file with no code found
		return false
	}

	/**
	 Checks if a declaration is inside a #if block and if that block would become empty after deletion.

	 Returns the adjusted deletion range if an empty #if block should be removed, otherwise returns nil.
	 */
	static func checkForEmptyConditionalBlock(
		lines: [String],
		startLine: Int,
		endLine: Int
	) -> (newStartLine: Int, newEndLine: Int)? {
		// Look backward for #if
		var ifLine: Int?
		var checkLine = startLine - 1

		while checkLine >= 1 {
			let lineIndex = checkLine - 1
			guard lineIndex >= 0, lineIndex < lines.count else { break }
			let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)

			if trimmed.isEmpty {
				checkLine -= 1
				continue
			}

			if trimmed.starts(with: "#if") {
				ifLine = checkLine
				break
			}

			// Stop if we hit non-empty, non-#if content
			if !trimmed.starts(with: "//") {
				break
			}

			checkLine -= 1
		}

		guard let foundIfLine = ifLine else { return nil }

		// Look forward for #endif
		var endifLine: Int?
		checkLine = endLine + 1

		while checkLine <= lines.count {
			let lineIndex = checkLine - 1
			guard lineIndex >= 0, lineIndex < lines.count else { break }
			let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)

			if trimmed.isEmpty {
				checkLine += 1
				continue
			}

			if trimmed.starts(with: "#endif") {
				endifLine = checkLine
				break
			}

			// Stop if we hit non-empty, non-#endif content
			if !trimmed.starts(with: "//") {
				break
			}

			checkLine += 1
		}

		guard let foundEndifLine = endifLine else { return nil }

		// Check if the block contains ONLY the declaration being deleted (and whitespace/comments)
		var hasOtherContent = false
		for lineNum in foundIfLine + 1 ..< foundEndifLine {
			// Skip the lines we're deleting
			if lineNum >= startLine, lineNum <= endLine {
				continue
			}

			let lineIndex = lineNum - 1
			guard lineIndex >= 0, lineIndex < lines.count else { continue }
			let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)

			// Skip empty lines and comments
			if trimmed.isEmpty || trimmed.starts(with: "//") || trimmed.starts(with: "/*") || trimmed
				.starts(with: "*") {
				continue
			}

			// Found other content
			hasOtherContent = true
			break
		}

		// If block would be empty, expand deletion to include #if and #endif
		if !hasOtherContent {
			return (newStartLine: foundIfLine, newEndLine: foundEndifLine)
		}

		return nil
	}
}
