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
	 Unified access control modification method.

	 Handles all access control fixes: removing redundant keywords or inserting suggested keywords.
	 Uses declaration.modifiers to verify current state and ensure correct modifications.
	 */
	static func fixAccessControl(
		declaration: Declaration,
		location: Location,
		fix: AccessControlFix
	) -> Result<ModificationResult, Error> {
		let filePath = location.file.path.string
		guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(CodeModificationError.cannotReadFile(filePath))
		}

		var lines = fileContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(CodeModificationError.invalidLineRange(location.line, lines.count))
		}

		let lineIndex = location.line - 1
		let originalLine = lines[lineIndex]
		var newLine = originalLine

		switch fix {
		case .removePublic:
			guard declaration.modifiers.contains("public") else {
				return .failure(CodeModificationError.patternNotFound("public modifier"))
			}
			newLine = originalLine.replacing(#/public\s+/#, with: "")

		case .removeInternal:
			guard declaration.modifiers.contains("internal") else {
				return .failure(CodeModificationError.patternNotFound("internal modifier"))
			}
			newLine = originalLine.replacing(#/internal\s+/#, with: "")

		case .removePrivate:
			guard declaration.modifiers.contains("private") else {
				return .failure(CodeModificationError.patternNotFound("private modifier"))
			}
			newLine = originalLine.replacing(#/private\s+/#, with: "")

		case .removeFilePrivate:
			guard declaration.modifiers.contains("fileprivate") else {
				return .failure(CodeModificationError.patternNotFound("fileprivate modifier"))
			}
			newLine = originalLine.replacing(#/fileprivate\s+/#, with: "")

		case let .removeAccessibility(current):
			// Try to remove any access keyword if present
			if current != nil {
				// Use provided keyword
				newLine = originalLine.replacing(#/public\s+|internal\s+|private\s+|fileprivate\s+|open\s+/#, with: "")
			} else {
				// Try each keyword
				for keyword in ["public", "internal", "private", "fileprivate", "open"] {
					if declaration.modifiers.contains(keyword) {
						let pattern = try? NSRegularExpression(pattern: "\(keyword)\\s+")
						if let pattern {
							let range = NSRange(originalLine.startIndex..., in: originalLine)
							newLine = pattern.stringByReplacingMatches(in: originalLine, range: range, withTemplate: "")
							break
						}
					}
				}
			}

		case .insertPrivate:
			// Find declaration keyword and insert "private " before it
			newLine = insertAccessKeyword("private", before: declaration.kind, in: originalLine)

		case .insertFilePrivate:
			// Find declaration keyword and insert "fileprivate " before it
			newLine = insertAccessKeyword("fileprivate", before: declaration.kind, in: originalLine)
		}

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
			linesRemoved: 0,
			startLine: location.line,
			endLine: location.line
		))
	}

	/**
	 Inserts an access keyword before a declaration keyword.

	 Finds the declaration keyword (func, var, class, etc.) and inserts the access keyword before it.
	 Does not insert before attributes like @State, @Published.
	 */
	private static func insertAccessKeyword(
		_ accessKeyword: String,
		before declarationKind: Declaration.Kind,
		in line: String
	) -> String {
		// Map declaration kind to keyword
		let declKeyword: String
		switch declarationKind {
		case .varParameter, .varLocal, .varGlobal, .varStatic, .varInstance, .varClass:
			declKeyword = "var"
		case .functionFree, .functionAccessorGetter, .functionAccessorSetter, .functionAccessorDidset,
		     .functionAccessorWillset, .functionAccessorAddress, .functionAccessorMutableaddress, .functionAccessorRead,
		     .functionAccessorModify, .functionAccessorInit, .functionConstructor, .functionDestructor,
		     .functionMethodClass, .functionMethodInstance, .functionMethodStatic, .functionOperator,
		     .functionOperatorInfix, .functionOperatorPostfix, .functionOperatorPrefix, .functionSubscript:
			declKeyword = "func"
		case .class:
			declKeyword = "class"
		case .struct:
			declKeyword = "struct"
		case .enum:
			declKeyword = "enum"
		case .enumelement:
			declKeyword = "case"
		case .protocol:
			declKeyword = "protocol"
		case .typealias:
			declKeyword = "typealias"
		case .associatedtype:
			declKeyword = "associatedtype"
		case .extension, .extensionClass, .extensionEnum, .extensionProtocol, .extensionStruct:
			declKeyword = "extension"
		case .macro:
			declKeyword = "macro"
		case .precedenceGroup:
			declKeyword = "precedencegroup"
		case .genericTypeParam:
			// Generic parameters don't have access keywords
			return line
		case .module:
			declKeyword = "import"
		}

		// Find the declaration keyword and insert access keyword before it
		if let range = line.range(of: "\\b\(declKeyword)\\b", options: .regularExpression) {
			return line.replacingCharacters(in: range, with: "\(accessKeyword) \(declKeyword)")
		} else {
			return line
		}
	}

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
