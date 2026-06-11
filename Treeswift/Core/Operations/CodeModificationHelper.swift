import Foundation
import PeripheryKit
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
		fileprivate let startLine: Int
		fileprivate let endLine: Int

		/**
		 Finds declarations affected by this modification and adjusts their line numbers.

		 Returns USRs of adjusted declarations for undo tracking.
		 Only performs adjustment if lines were actually removed.
		 */
		func adjustSourceGraph(_ sourceGraph: any SourceGraphProtocol) -> [String] {
			guard linesRemoved > 0 else { return [] }

			return SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: sourceGraph,
				filePath: filePath,
				afterLine: endLine,
				lineDelta: -linesRemoved
			)
		}
	}

	// MARK: - Empty Container Detection

	/**
	 Finds the highest ancestor container that would become empty after deleting the given declaration.

	 Walks up the parent chain to find containers whose children are ALL being deleted in this batch.
	 Returns the highest such ancestor, or the original declaration if no parents would become empty.

	 The `allDeletingUSRs` parameter contains USRs of all declarations being deleted in the batch,
	 enabling detection of cases where multiple siblings are all being removed (e.g., deleting both
	 members of an extension should delete the extension itself).
	 */
	private static func findHighestEmptyAncestor(
		of declaration: Declaration,
		allDeletingUSRs: Set<String>,
		sourceGraph: (any SourceGraphProtocol)? = nil
	) -> Declaration {
		var current = declaration

		while let parent = current.parent {
			// If the parent is explicitly retained by a mutator (e.g., ObservableMacroRetainer),
			// do not promote — the parent must stay even if all its explicit children are flagged.
			if let sourceGraph, sourceGraph.isRetained(parent) {
				fputs(
					"DEBUG findHighestEmptyAncestor: parent \(parent.name) is retained — not promoting \(declaration.name)\n",
					stderr
				)
				break
			}

			// Check if ALL children would be removed after deleting current.
			// Every child (including enum cases) must be explicitly in allDeletingUSRs to
			// allow parent promotion. Enum cases that are used externally are not in
			// allDeletingUSRs and should block parent promotion.
			// Guard against vacuous truth: an empty declarations set satisfies allSatisfy,
			// but an empty container (e.g. `extension Type: Protocol {}`) should never be
			// promoted to automatically.
			guard !parent.declarations.isEmpty else { break }
			let allChildrenDeleted = parent.declarations.allSatisfy { sibling in
				sibling.usrs.contains { allDeletingUSRs.contains($0) }
			}
			if allChildrenDeleted {
				fputs(
					"DEBUG findHighestEmptyAncestor: ALL children of \(parent.name) in allDeletingUSRs — promoting \(declaration.name) → \(parent.name)\n",
					stderr
				)
			}
			guard allChildrenDeleted else { break }
			current = parent
		}

		return current
	}

	// MARK: - Access Control Helpers

	/**
	 Removes an access keyword from a line, preserving whitespace.
	 */
	private static func removeAccessKeyword(_ keyword: String, from line: String) -> String {
		guard let pattern = try? Regex("\\b\(keyword)\\s+") else { return line }
		return line.replacing(pattern, with: "")
	}

	/**
	 Replaces an access keyword with another, preserving whitespace.
	 */
	private static func replaceAccessKeyword(
		_ oldKeyword: String,
		with newKeyword: String,
		in line: String
	) -> String {
		guard let pattern = try? Regex("\\b\(oldKeyword)\\s+") else { return line }
		return line.replacing(pattern, with: "\(newKeyword) ")
	}

	/**
	 Removes any access keyword from a line, preserving whitespace.
	 */
	private static func removeAnyAccessKeyword(from line: String) -> String {
		var modifiedLine = line
		for keyword in ["public", "internal", "fileprivate", "private"] {
			if let pattern = try? Regex("\\b\(keyword)\\s+") {
				modifiedLine = modifiedLine.replacing(pattern, with: "")
			}
		}
		return modifiedLine
	}

	/**
	 Removes a setter-specific modifier (e.g. `private(set)`, `internal(set)`) from a line.
	 */
	private static func removeSetterModifier(from line: String) -> String {
		guard let setterPattern = try? Regex("\\b(public|internal|fileprivate|private)\\(set\\)\\s*")
		else { return line }
		return line.replacing(setterPattern, with: "")
	}

	/**
	 Replaces or inserts an access keyword in a line, removing any setter-specific
	 modifiers (e.g. `private(set)`, `internal(set)`) that would conflict.

	 Returns both the modified line and a description of the action taken.
	 */
	private static func replaceOrInsertAccessKeyword(
		oldKeyword: String?,
		newKeyword: String,
		declarationKind: Declaration.Kind,
		in line: String
	) -> (line: String, action: String) {
		// Remove any setter-specific modifier (e.g. "private(set) ", "internal(set) ")
		// before replacing/inserting the main access keyword
		var workingLine = line
		var removedSetterModifier: String?
		if let setterPattern = try? Regex("\\b(public|internal|fileprivate|private)\\(set\\)\\s*") {
			if let match = workingLine.firstMatch(of: setterPattern) {
				let matchedText = String(workingLine[match.range])
				removedSetterModifier = matchedText.trimmingCharacters(in: .whitespaces)
				workingLine.replaceSubrange(match.range, with: "")
			}
		}

		// First try to replace the expected old keyword.
		if let oldKeyword,
		   let pattern = try? Regex("\\b\(oldKeyword)\\s+"),
		   workingLine.contains(pattern) {
			let result = replaceAccessKeyword(oldKeyword, with: newKeyword, in: workingLine)
			return (result, "replaced `\(oldKeyword)` with `\(newKeyword)`")
		}

		// If expected keyword not found, check for any other existing access keyword.
		// This prevents inserting a second keyword (e.g. producing `private private var`
		// or `public private var`) when the declaration already has an explicit access level.
		for existingKeyword in ["public", "fileprivate", "private", "internal"] {
			guard let pattern = try? Regex("\\b\(existingKeyword)\\s+"),
			      workingLine.contains(pattern) else { continue }
			let result = replaceAccessKeyword(existingKeyword, with: newKeyword, in: workingLine)
			return (result, "replaced `\(existingKeyword)` with `\(newKeyword)`")
		}

		// No existing access keyword — safe to insert.
		let result = insertAccessKeyword(newKeyword, before: declarationKind, in: workingLine)
		let action = if let removedSetterModifier {
			"replaced `\(removedSetterModifier)` with `\(newKeyword)`"
		} else {
			"inserted `\(newKeyword)`"
		}
		return (result, action)
	}

	// MARK: - Access Control Modifications

	/**
	 Fixes redundant or incorrect access control by removing or inserting access keywords.

	 Handles all access control warning types:
	 - removePublic/Internal/FilePrivate/Private: Removes the specified keyword (becomes internal)
	 - removeAccessibility: Removes any access keyword present
	 - insertPrivate/FilePrivate: Inserts keyword before declaration keyword
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
		let newLine: String

		switch fix {
		case .removePublic:
			guard declaration.modifiers.contains("public") else {
				return .failure(CodeModificationError.patternNotFound("public modifier"))
			}
			newLine = removeAccessKeyword("public", from: originalLine)

		case .removeInternal:
			// Internal is the default, so keyword may not be present - just try to remove it
			newLine = removeAccessKeyword("internal", from: originalLine)

		case .removePrivate:
			guard declaration.modifiers.contains("private") else {
				return .failure(CodeModificationError.patternNotFound("private modifier"))
			}
			newLine = removeAccessKeyword("private", from: originalLine)

		case .removeFilePrivate:
			guard declaration.modifiers.contains("fileprivate") else {
				return .failure(CodeModificationError.patternNotFound("fileprivate modifier"))
			}
			newLine = removeAccessKeyword("fileprivate", from: originalLine)

		case let .removeAccessibility(current):
			if let current {
				newLine = removeAccessKeyword(current, from: originalLine)
			} else {
				newLine = removeAnyAccessKeyword(from: originalLine)
			}

		case .insertPrivate:
			// Remove any explicit 'internal' keyword and setter modifiers before inserting 'private'
			var workingLine = removeAccessKeyword("internal", from: originalLine)
			workingLine = removeSetterModifier(from: workingLine)
			newLine = insertAccessKeyword("private", before: declaration.kind, in: workingLine)

		case .insertFilePrivate:
			// Remove any explicit 'internal' keyword and setter modifiers before inserting 'fileprivate'
			var workingLine = removeAccessKeyword("internal", from: originalLine)
			workingLine = removeSetterModifier(from: workingLine)
			newLine = insertAccessKeyword("fileprivate", before: declaration.kind, in: workingLine)
		}

		lines[lineIndex] = newLine
		let modifiedContents = lines.joined(separator: "\n")

		// Write back to file
		do {
			try modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(CodeModificationError.cannotWriteFile(filePath))
		}

		ModificationLogger.log(
			filePath: filePath,
			startLine: location.line,
			endLine: location.line,
			action: fix.logDescription
		)

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
	 Inserts an access keyword before a declaration keyword in a source line.

	 Finds the declaration keyword based on Declaration.Kind and inserts the access
	 keyword with a space before it. Does not insert before attributes like @State.
	 */
	private static func insertAccessKeyword(
		_ keyword: String,
		before kind: Declaration.Kind,
		in line: String
	) -> String {
		let declarationKeyword: String = switch kind {
		case .varInstance, .varStatic, .varLocal, .varClass, .varParameter, .varGlobal:
			line.contains("let ") ? "let" : "var"
		case .functionFree, .functionOperator, .functionOperatorPrefix, .functionOperatorPostfix,
		     .functionOperatorInfix,
		     .functionMethodClass, .functionMethodInstance, .functionMethodStatic, .functionAccessorGetter,
		     .functionAccessorSetter, .functionAccessorDidset, .functionAccessorWillset,
		     .functionAccessorMutableaddress,
		     .functionAccessorAddress, .functionAccessorRead, .functionAccessorModify, .functionAccessorInit,
		     .functionSubscript, .functionConstructor, .functionDestructor:
			kind == .functionSubscript ? "subscript" :
				(kind == .functionConstructor ? "init" : (kind == .functionDestructor ? "deinit" : "func"))
		case .class:
			"class"
		case .struct:
			"struct"
		case .enum:
			"enum"
		case .enumelement:
			"case"
		case .protocol:
			"protocol"
		case .typealias:
			"typealias"
		case .associatedtype:
			"associatedtype"
		case .extension, .extensionClass, .extensionStruct, .extensionProtocol, .extensionEnum:
			"extension"
		case .macro:
			"macro"
		case .precedenceGroup:
			"precedencegroup"
		case .genericTypeParam:
			"typealias"
		case .module:
			"import"
		}

		// Candidate source keywords for this kind. Periphery (via the Swift index store) classifies
		// an `actor` as `.class` — its `Kind` has no dedicated actor case — so a `.class`-kind
		// declaration may actually read `actor` in source. Search for whichever keyword is present.
		let candidateKeywords: [String] = declarationKeyword == "class" ? ["class", "actor"] : [declarationKeyword]

		// Find the declaration keyword and insert the access keyword before it. Match on a word
		// boundary so e.g. `class` does not match inside `classify`. If none of the candidate
		// keywords is found on this line (e.g. the location maps to a wrong source line from a macro
		// expansion), return the line unchanged to avoid corrupting unrelated code.
		var matched: (keyword: String, range: Range<String.Index>)?
		for candidate in candidateKeywords {
			if let r = line.range(of: "\\b\(candidate)\\b", options: .regularExpression) {
				matched = (candidate, r)
				break
			}
		}
		guard let (foundKeyword, range) = matched else {
			return line
		}

		// Guard against inserting into control-flow `let`/`var` bindings (e.g. `if let`, `guard let`,
		// `while let`, `for var`). These look like declarations but aren't — inserting an access
		// keyword before them produces invalid Swift (`if private let x = ...`).
		// Check that the token immediately before the keyword (ignoring leading whitespace) is not
		// a control-flow keyword.
		if foundKeyword == "let" || foundKeyword == "var" {
			let prefix = String(line[line.startIndex ..< range.lowerBound])
				.trimmingCharacters(in: .whitespaces)
			let controlFlowKeywords = ["if", "guard", "while", "for", ","]
			let lastToken = prefix.components(separatedBy: .whitespaces).last ?? ""
			if controlFlowKeywords.contains(lastToken) {
				return line
			}
		}

		return line.replacingCharacters(in: range, with: "\(keyword) \(foundKeyword)")
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

		ModificationLogger.log(
			filePath: filePath,
			startLine: startLine,
			endLine: endLine,
			action: "removed `periphery:ignore` comment"
		)

		return .success(ModificationResult(
			filePath: filePath,
			originalContents: fileContents,
			modifiedContents: modifiedContents,
			linesRemoved: linesRemoved,
			startLine: startLine,
			endLine: endLine
		))
	}

	// MARK: - Execution Methods (with undo/redo support)

	/**
	 Executes declaration deletion with smart boundary detection.

	 Deletes a declaration from source code, including its attributes and comments.
	 Handles source graph line number adjustments and registers undo/redo.
	 */
	@MainActor
	static func executeDeclarationDeletion(
		declaration: Declaration,
		location: Location,
		sourceGraph: (any SourceGraphProtocol)?,
		undoManager: UndoManager?,
		warningID: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) -> Result<Void, Error> {
		let filePath = location.file.path.string

		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(CodeModificationError.cannotReadFile(filePath))
		}

		var lines = originalContents.components(separatedBy: .newlines)

		// Special handling for enum cases on the same line as other cases
		if declaration.kind == .enumelement {
			// Extract the case name from the declaration
			let caseName = declaration.name
			if !caseName.isEmpty,
			   let modifiedLines = DeclarationDeletionHelper.handleInlineEnumCaseDeletion(
			   	lines: lines,
			   	declarationLine: location.line,
			   	caseName: caseName
			   ) {
				// Successfully handled inline case deletion
				let modifiedContents = modifiedLines.joined(separator: "\n")

				// Write back to file
				do {
					try modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
				} catch {
					return .failure(CodeModificationError.cannotWriteFile(filePath))
				}

				// Invalidate cache
				SourceFileReader.invalidateCache(for: filePath)

				ModificationLogger.log(
					filePath: filePath,
					startLine: location.line,
					endLine: location.line,
					action: "removed enum case `\(caseName)`"
				)

				// Register undo (no line number adjustments needed - we only modified one line)
				UndoRedoHelper.registerDeletionUndo(
					undoManager: undoManager,
					originalContents: originalContents,
					modifiedContents: modifiedContents,
					filePath: filePath,
					warningID: warningID,
					adjustedUSRs: [],
					lineAdjustment: 0,
					sourceGraph: sourceGraph,
					actionName: "Delete Enum Case",
					onComplete: onComplete,
					onRestore: onRestore
				)

				onComplete()
				return .success(())
			}
		}

		// Check if parent should be deleted instead (empty container removal)
		let deletingUSRs = Set(declaration.usrs)
		let actualTarget = findHighestEmptyAncestor(
			of: declaration,
			allDeletingUSRs: deletingUSRs,
			sourceGraph: sourceGraph
		)

		// Use the actual target's location for deletion
		let targetLocation = actualTarget.location
		guard let endLine = targetLocation.endLine else {
			return .failure(CodeModificationError.missingEndLocation)
		}

		// Find deletion boundaries using smart boundary detection
		let startLine = DeclarationDeletionHelper.findDeletionStartLine(
			lines: lines,
			declarationLine: targetLocation.line,
			attributes: actualTarget.attributes
		)

		// Determine ending line (includes smart blank line handling)
		var finalStartLine = startLine
		var finalEndLine = DeclarationDeletionHelper.findDeletionEndLine(
			lines: lines,
			declarationLine: targetLocation.line,
			declarationEndLine: endLine
		)

		// Check if we're inside an empty #if block
		if let adjustedRange = DeclarationDeletionHelper.checkForEmptyConditionalBlock(
			lines: lines,
			startLine: finalStartLine,
			endLine: finalEndLine
		) {
			finalStartLine = adjustedRange.newStartLine
			finalEndLine = adjustedRange.newEndLine
		}

		// Validate range
		guard finalStartLine > 0, finalEndLine > 0,
		      finalStartLine <= lines.count, finalEndLine <= lines.count,
		      finalStartLine <= finalEndLine else {
			return .failure(CodeModificationError.invalidLineRange(finalStartLine, lines.count))
		}

		// Delete the range
		let startIndex = finalStartLine - 1
		let endIndex = finalEndLine - 1
		lines.removeSubrange(startIndex ... endIndex)

		// Write back
		let modifiedContents = lines.joined(separator: "\n")
		do {
			try modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(CodeModificationError.cannotWriteFile(filePath))
		}

		// Invalidate source file cache
		SourceFileReader.invalidateCache(for: filePath)

		ModificationLogger.log(
			filePath: filePath,
			startLine: finalStartLine,
			endLine: finalEndLine,
			action: "Deleted"
		)

		// Adjust line numbers and track which declarations were adjusted
		let linesRemoved = finalEndLine - finalStartLine + 1
		let afterLine = finalEndLine

		let adjustedUSRs: [String] = if let sourceGraph {
			SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: sourceGraph,
				filePath: filePath,
				afterLine: afterLine,
				lineDelta: -linesRemoved
			)
		} else {
			[]
		}

		// Register undo
		UndoRedoHelper.registerDeletionUndo(
			undoManager: undoManager,
			originalContents: originalContents,
			modifiedContents: modifiedContents,
			filePath: filePath,
			warningID: warningID,
			adjustedUSRs: adjustedUSRs,
			lineAdjustment: linesRemoved,
			sourceGraph: sourceGraph,
			actionName: "Delete Declaration",
			onComplete: onComplete,
			onRestore: onRestore
		)

		// Call completion callback
		onComplete()

		return .success(())
	}

	/**
	 Executes simple declaration deletion without smart boundary detection.

	 Falls back to basic line-range deletion when sourceGraph is unavailable.
	 Used when the declaration has full range info but no sourceGraph context.
	 */
	@MainActor
	static func executeSimpleDeclarationDeletion(
		declaration: Declaration,
		location: Location,
		sourceGraph: (any SourceGraphProtocol)?,
		undoManager: UndoManager?,
		warningID: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) -> Result<Void, Error> {
		guard let endLine = location.endLine, location.endColumn != nil else {
			return .failure(CodeModificationError.missingEndLocation)
		}

		let filePath = location.file.path.string

		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(CodeModificationError.cannotReadFile(filePath))
		}

		// Delete the declaration range
		var lines = originalContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(CodeModificationError.invalidLineRange(location.line, lines.count))
		}
		guard endLine > 0, endLine <= lines.count else {
			return .failure(CodeModificationError.invalidLineRange(endLine, lines.count))
		}

		// Remove lines from startLine to endLine (inclusive)
		let startIndex = location.line - 1
		let endIndex = endLine - 1
		lines.removeSubrange(startIndex ... endIndex)

		// Write back to file
		let newContents = lines.joined(separator: "\n")
		do {
			try newContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(CodeModificationError.cannotWriteFile(filePath))
		}

		// Invalidate source file cache
		SourceFileReader.invalidateCache(for: filePath)

		ModificationLogger.log(
			filePath: filePath,
			startLine: location.line,
			endLine: endLine,
			action: "Deleted"
		)

		// Adjust line numbers and track which declarations were adjusted
		let linesRemoved = endLine - location.line + 1
		let afterLine = endLine

		let adjustedUSRs: [String] = if let sourceGraph {
			SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: sourceGraph,
				filePath: filePath,
				afterLine: afterLine,
				lineDelta: -linesRemoved
			)
		} else {
			[]
		}

		// Register undo
		UndoRedoHelper.registerDeletionUndo(
			undoManager: undoManager,
			originalContents: originalContents,
			modifiedContents: newContents,
			filePath: filePath,
			warningID: warningID,
			adjustedUSRs: adjustedUSRs,
			lineAdjustment: linesRemoved,
			sourceGraph: sourceGraph,
			actionName: "Delete Declaration",
			onComplete: onComplete,
			onRestore: onRestore
		)

		// Call completion callback
		onComplete()

		return .success(())
	}

	/**
	 Executes import statement deletion.

	 Deletes a single import line and adjusts line numbers in the source graph.
	 */
	@MainActor
	static func executeImportDeletion(
		location: Location,
		sourceGraph: (any SourceGraphProtocol)?,
		undoManager: UndoManager?,
		warningID: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) -> Result<Void, Error> {
		let filePath = location.file.path.string

		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(CodeModificationError.cannotReadFile(filePath))
		}

		// Delete the single import line
		var lines = originalContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(CodeModificationError.invalidLineRange(location.line, lines.count))
		}

		// Remove the import line
		let lineIndex = location.line - 1
		lines.remove(at: lineIndex)

		// Write back to file
		let newContents = lines.joined(separator: "\n")
		do {
			try newContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(CodeModificationError.cannotWriteFile(filePath))
		}

		// Invalidate source file cache
		SourceFileReader.invalidateCache(for: filePath)

		ModificationLogger.log(
			filePath: filePath,
			startLine: location.line,
			endLine: location.line,
			action: "Deleted import"
		)

		// Adjust line numbers and track which declarations were adjusted
		let afterLine = location.line

		let adjustedUSRs: [String] = if let sourceGraph {
			SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: sourceGraph,
				filePath: filePath,
				afterLine: afterLine,
				lineDelta: -1 // Removed one line
			)
		} else {
			[]
		}

		// Register undo
		UndoRedoHelper.registerDeletionUndo(
			undoManager: undoManager,
			originalContents: originalContents,
			modifiedContents: newContents,
			filePath: filePath,
			warningID: warningID,
			adjustedUSRs: adjustedUSRs,
			lineAdjustment: 1, // One line removed
			sourceGraph: sourceGraph,
			actionName: "Delete Import",
			onComplete: onComplete,
			onRestore: onRestore
		)

		// Call completion callback
		onComplete()

		return .success(())
	}

	/**
	 Executes ignore comment insertion.

	 Inserts a "// periphery:ignore" comment above the declaration,
	 including attributes and comments. Adjusts line numbers and registers undo/redo.
	 */
	@MainActor
	static func executeIgnoreCommentInsertion(
		declaration: Declaration,
		location: Location,
		sourceGraph: (any SourceGraphProtocol)?,
		undoManager: UndoManager?,
		warningID: String,
		onComplete: @escaping () -> Void,
		onRestore: @escaping () -> Void
	) -> Result<Void, Error> {
		let filePath = location.file.path.string

		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(CodeModificationError.cannotReadFile(filePath))
		}

		var lines = originalContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else {
			return .failure(CodeModificationError.invalidLineRange(location.line, lines.count))
		}

		// Find the insertion line (stops before documentation comments, unlike deletion logic)
		let insertionLine = DeclarationDeletionHelper.findIgnoreCommentInsertionLine(
			lines: lines,
			declarationLine: location.line,
			attributes: declaration.attributes
		)

		// Insert the ignore directive
		let insertIndex = insertionLine - 1
		lines.insert("// periphery:ignore", at: insertIndex)

		// Write back to file
		let modifiedContents = lines.joined(separator: "\n")
		do {
			try modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(CodeModificationError.cannotWriteFile(filePath))
		}

		// Invalidate cache
		SourceFileReader.invalidateCache(for: filePath)

		ModificationLogger.log(
			filePath: filePath,
			startLine: insertionLine,
			endLine: insertionLine,
			action: "inserted `// periphery:ignore`"
		)

		// Adjust line numbers for declarations after this one
		let adjustedUSRs: [String] = if let sourceGraph {
			SourceGraphLineAdjuster.adjustAndTrack(
				sourceGraph: sourceGraph,
				filePath: filePath,
				afterLine: insertionLine - 1, // Line before insertion
				lineDelta: 1 // Added one line
			)
		} else {
			[]
		}

		// Register undo (note: for insertion, we negate the line adjustment)
		UndoRedoHelper.registerDeletionUndo(
			undoManager: undoManager,
			originalContents: originalContents,
			modifiedContents: modifiedContents,
			filePath: filePath,
			warningID: warningID,
			adjustedUSRs: adjustedUSRs,
			lineAdjustment: -1, // Negative because we added a line (undo removes it)
			sourceGraph: sourceGraph,
			actionName: "Insert Ignore Comment",
			onComplete: onComplete,
			onRestore: onRestore
		)

		// Call completion callback
		onComplete()

		return .success(())
	}

	// MARK: - Fileprivate Cascade

	/**
	 Cascades `fileprivate` to sibling `init` and `func` declarations whose signatures
	 reference a type that was just made `fileprivate`.

	 Swift requires that any initializer or function whose parameter or return type is
	 `fileprivate` must itself be `fileprivate`. When Treeswift inserts `fileprivate` on a
	 nested enum/struct/class, this method finds sibling declarations in the same enclosing
	 scope that reference that type and adds `fileprivate` to them if they carry no explicit
	 access modifier.

	 Algorithm:
	 1. For each `(lineIndex, typeName)` pair, walk backwards from `lineIndex` counting
	    braces to locate the opening `{` of the parent type body.
	 2. Walk forwards from `lineIndex` to find the matching closing `}`.
	 3. Within that range, scan for `init(` or `func ` lines that mention `typeName` in
	    their signature and lack an explicit access keyword — then insert `fileprivate`.
	 */
	/**
	 Locates the line index for a `fileprivate` type declaration in `lines`, searching
	 outward from `near` to handle index shifts caused by earlier deletions.

	 Returns nil if no matching line is found within a reasonable window.
	 */
	private static func findFileprivateTypeLine(
		typeName: String,
		near storedIndex: Int,
		in lines: [String]
	) -> Int? {
		guard let pattern = try? Regex("\\bfileprivate\\b.+\\b(enum|struct|class)\\s+\(typeName)\\b")
		else { return nil }
		// Search within ±5 lines of the stored index to tolerate small index shifts.
		let searchRadius = 5
		let low = max(0, storedIndex - searchRadius)
		let high = min(lines.count - 1, storedIndex + searchRadius)
		for idx in low ... high {
			if lines[idx].contains(pattern) {
				return idx
			}
		}
		return nil
	}

	private static func cascadeFileprivateToAffectedDeclarations(
		lines: [String],
		fileprivateNestedTypeNames: [(lineIndex: Int, typeName: String)],
		pendingLogEntries: inout [ModificationLogger.PendingEntry]
	) -> [String] {
		var lines = lines

		for (storedLineIndex, typeName) in fileprivateNestedTypeNames {
			// Resolve the current line index for this type in the (possibly modified) lines array.
			// We search for the fileprivate type declaration near the stored index to handle any
			// index shifts from earlier deletions in the same batch.
			guard let typeLineIndex = Self.findFileprivateTypeLine(
				typeName: typeName,
				near: storedLineIndex,
				in: lines
			) else { continue }

			// Walk backwards from the line above the type to find the enclosing scope's `{`.
			// We start one line above the type's own line so we don't mistake the type's own
			// `{` for the parent's opening brace. Scanning characters in reverse: `}` increases
			// depth, `{` decreases. When depth is 0 and we encounter `{`, that is the parent
			// body's opening brace.
			var depth = 0
			var scopeStart: Int?
			let searchFrom = max(typeLineIndex - 1, 0)
			outer: for idx in stride(from: searchFrom, through: 0, by: -1) {
				for ch in lines[idx].reversed() {
					if ch == "}" {
						depth += 1
					} else if ch == "{" {
						if depth == 0 {
							scopeStart = idx
							break outer
						}
						depth -= 1
					}
				}
			}
			guard let scopeStart else { continue }

			// Walk forward from the parent opening brace to find the matching closing `}`.
			depth = 0
			var scopeEnd: Int?
			outer: for idx in scopeStart ..< lines.count {
				for ch in lines[idx] {
					if ch == "{" {
						depth += 1
					} else if ch == "}" {
						depth -= 1
						if depth == 0 {
							scopeEnd = idx
							break outer
						}
					}
				}
			}
			guard let scopeEnd else { continue }

			// Compile patterns once per type name.
			guard let typePattern = try? Regex("\\b\(typeName)\\b"),
			      let funcPattern = try? Regex("\\bfunc\\s+\\w"),
			      // Matches declarations that already have a non-private access modifier
			      // before func/init. `private` is excluded because `private init` referencing
			      // a `fileprivate` type must be upgraded to `fileprivate`, not skipped.
			      let nonPrivateAccessedInitOrFuncPattern = try? Regex(
			      	"\\b(public|internal|fileprivate)\\s+(func|init)\\b"
			      ),
			      let privateInitOrFuncPattern = try? Regex(
			      	"\\bprivate\\s+(func|init)\\b"
			      ) else { continue }

			// Scan lines within the parent scope for `init` or `func` declarations that:
			//  - have the fileprivate type name somewhere in their signature
			//  - do not already have a non-upgradeable access modifier
			//
			// Because signatures can span multiple lines (e.g. multi-line init parameter
			// lists), we detect the declaration keyword line first, then collect the full
			// signature text up to the closing `)` before checking for the type name.
			var idx = scopeStart
			while idx <= scopeEnd {
				let line = lines[idx]

				// Must be an init or func declaration line (keyword must appear here)
				let isInit = line.contains("init(")
				let isFunc = line.firstMatch(of: funcPattern) != nil
				guard isInit || isFunc else {
					idx += 1
					continue
				}

				// Skip if already has a non-private access modifier (public/internal/fileprivate).
				// These are either already correct or indicate a different access level intent.
				// `private` is NOT skipped here because `private init/func` referencing a
				// `fileprivate` type needs to be upgraded to `fileprivate`.
				if line.contains(nonPrivateAccessedInitOrFuncPattern) {
					idx += 1
					continue
				}

				// Detect whether the declaration already has `private` before init/func,
				// which means we need to replace `private` with `fileprivate` rather than insert.
				let alreadyPrivate = line.contains(privateInitOrFuncPattern)

				// Also skip if any non-private standalone access keyword leads the declaration
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				let hasNonPrivateLeadingAccess = ["public ", "internal ", "fileprivate "].contains {
					trimmed.hasPrefix($0)
				}
				if hasNonPrivateLeadingAccess {
					idx += 1
					continue
				}

				// Collect the full signature text (from this line to the closing `)`)
				// by counting unmatched parentheses across subsequent lines.
				var signatureLines = [line]
				var parenDepth = line.count(where: { $0 == "(" }) - line.count(where: { $0 == ")" })
				var sigEnd = idx
				while parenDepth > 0, sigEnd + 1 <= scopeEnd {
					sigEnd += 1
					let sigLine = lines[sigEnd]
					signatureLines.append(sigLine)
					parenDepth += sigLine.count(where: { $0 == "(" })
					parenDepth -= sigLine.count(where: { $0 == ")" })
				}
				let fullSignature = signatureLines.joined(separator: "\n")

				// Only cascade if the type name appears in the signature
				guard fullSignature.contains(typePattern) else {
					idx = sigEnd + 1
					continue
				}

				// Insert or replace access keyword with `fileprivate` on the declaration line.
				// If the declaration already has `private`, replace it; otherwise insert fresh.
				let kind: Declaration.Kind = isInit ? .functionConstructor : .functionMethodInstance
				let (modified, action) = replaceOrInsertAccessKeyword(
					oldKeyword: alreadyPrivate ? "private" : nil,
					newKeyword: "fileprivate",
					declarationKind: kind,
					in: line
				)
				if modified != line {
					lines[idx] = modified
					pendingLogEntries.append(.init(
						startLine: idx + 1,
						endLine: idx + 1,
						action: "\(action) (cascade from fileprivate `\(typeName)`)"
					))
				}
				idx = sigEnd + 1
			}
		}
		return lines
	}

	// MARK: - Public-to-Extension Cascade

	/**
	 Strips `public` from declarations inside `extension <TypeName>` blocks for every type
	 whose own `public` was just removed.

	 Swift requires that a member's declared access not exceed the effective access of its
	 extension, which inherits the extended type's access. Once Treeswift downgrades a type
	 from `public` to internal (a `redundantPublicAccessibility` fix), any `public` member in
	 that type's extensions becomes illegal ("cannot declare a public initializer in an
	 extension with internal requirements"). Periphery flags the type but not the extension
	 member, so this keeps the rewrite self-consistent.

	 Algorithm: scan for `extension <TypeName>` opening lines; within each block (matched by
	 brace depth) remove a leading `public ` from the extension declaration itself and from
	 every member declaration line. Conservative — only strips an explicit leading `public `.
	 */
	private static func cascadePublicStripFromExtensions(
		lines: [String],
		downgradedTypeNames: Set<String>,
		pendingLogEntries: inout [ModificationLogger.PendingEntry]
	) -> [String] {
		var lines = lines

		// Match `extension <TypeName>` where TypeName is one of the downgraded types. The
		// extension may carry generic constraints / conformances after the name, so match a
		// word boundary after the name rather than end-of-token.
		let alternation = downgradedTypeNames
			.map { NSRegularExpression.escapedPattern(for: $0) }
			.joined(separator: "|")
		guard !alternation.isEmpty,
		      let extensionPattern = try? Regex("\\bextension\\s+(?:\(alternation))\\b")
		else { return lines }

		var idx = 0
		while idx < lines.count {
			guard lines[idx].contains(extensionPattern) else {
				idx += 1
				continue
			}

			// Strip a leading `public ` from the extension declaration line itself.
			lines[idx] = stripLeadingPublic(from: lines[idx], at: idx, pendingLogEntries: &pendingLogEntries)

			// Find the extension body's opening `{` and its matching `}` by brace depth.
			var depth = 0
			var seenBrace = false
			var bodyEnd: Int?
			var scan = idx
			outer: while scan < lines.count {
				for ch in lines[scan] {
					if ch == "{" {
						depth += 1
						seenBrace = true
					} else if ch == "}" {
						depth -= 1
						if seenBrace, depth == 0 {
							bodyEnd = scan
							break outer
						}
					}
				}
				scan += 1
			}
			guard let bodyEnd else { idx += 1; continue }

			// Strip a leading `public ` from each member declaration line in the body.
			if bodyEnd > idx {
				for member in (idx + 1) ..< bodyEnd {
					lines[member] = stripLeadingPublic(
						from: lines[member],
						at: member,
						pendingLogEntries: &pendingLogEntries
					)
				}
			}
			idx = bodyEnd + 1
		}
		return lines
	}

	/**
	 Removes a single leading `public ` modifier (after indentation) from a declaration line,
	 logging the change. Returns the line unchanged if it has no leading `public `.
	 */
	private static func stripLeadingPublic(
		from line: String,
		at lineIndex: Int,
		pendingLogEntries: inout [ModificationLogger.PendingEntry]
	) -> String {
		let leadingWhitespace = String(line.prefix { $0 == " " || $0 == "\t" })
		let rest = line[line.index(line.startIndex, offsetBy: leadingWhitespace.count)...]
		guard rest.hasPrefix("public ") else { return line }
		let newLine = leadingWhitespace + rest.dropFirst("public ".count)
		pendingLogEntries.append(.init(
			startLine: lineIndex + 1,
			endLine: lineIndex + 1,
			action: "removed `public` (cascade from downgraded type's extension)"
		))
		return newLine
	}

	// MARK: - Fileprivate Function Cascade

	/**
	 Inserts `fileprivate` on any `func` — extension method or free function — whose signature
	 references a type that was just narrowed to `fileprivate`, when the func carries no explicit
	 access keyword.

	 Swift requires a function whose parameter or return type is `fileprivate` to be at most
	 `fileprivate` ("method must be declared fileprivate because its result uses a fileprivate
	 type"). The same-scope sibling cascade only patches inits/funcs inside the type's own parent
	 body; it does not reach `extension <Other> { func … -> [FileprivateType] }` or top-level free
	 functions. This pass closes that gap file-wide.

	 Conservative: only patches a `func` line that has no leading access keyword (so it can't lower
	 an intentionally-public API), and only when the type name appears in the collected signature.
	 */
	private static func cascadeFileprivateToReferencingFunctions(
		lines: [String],
		fileprivateTypeNames: Set<String>,
		pendingLogEntries: inout [ModificationLogger.PendingEntry]
	) -> [String] {
		var lines = lines

		let alternation = fileprivateTypeNames
			.map { NSRegularExpression.escapedPattern(for: $0) }
			.joined(separator: "|")
		guard !alternation.isEmpty,
		      let typeRefPattern = try? Regex("\\b(?:\(alternation))\\b"),
		      let funcKeywordPattern = try? Regex("\\bfunc\\b")
		else { return lines }

		var idx = 0
		while idx < lines.count {
			let line = lines[idx]
			// Must be a `func` declaration line with no explicit leading access modifier.
			guard line.contains(funcKeywordPattern) else { idx += 1; continue }
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			let hasLeadingAccess = ["public ", "internal ", "fileprivate ", "private ", "open "]
				.contains { trimmed.hasPrefix($0) }
			if hasLeadingAccess { idx += 1; continue }

			// Collect the full signature: from this line through the line that closes the
			// parameter list, plus that line's remainder (which carries the `-> ReturnType`).
			var sigEnd = idx
			var parenDepth = line.count(where: { $0 == "(" }) - line.count(where: { $0 == ")" })
			while parenDepth > 0, sigEnd + 1 < lines.count {
				sigEnd += 1
				parenDepth += lines[sigEnd].count(where: { $0 == "(" })
				parenDepth -= lines[sigEnd].count(where: { $0 == ")" })
			}
			let signature = lines[idx ... sigEnd].joined(separator: "\n")

			// Only cascade when the signature references a fileprivate type.
			guard signature.contains(typeRefPattern) else { idx = sigEnd + 1; continue }

			// Insert `fileprivate` before `func` (or before a leading `static`/`class` specifier).
			let newLine = insertFileprivateBeforeFunc(in: line)
			if newLine != line {
				lines[idx] = newLine
				pendingLogEntries.append(.init(
					startLine: idx + 1,
					endLine: idx + 1,
					action: "inserted `fileprivate` (cascade: func references a fileprivate type)"
				))
			}
			idx = sigEnd + 1
		}
		return lines
	}

	/**
	 Inserts `fileprivate ` before the `func` keyword on a declaration line, preserving leading
	 whitespace and any `static`/`class`/`mutating`/`nonmutating` specifier that precedes `func`.
	 */
	private static func insertFileprivateBeforeFunc(in line: String) -> String {
		let leadingWhitespace = String(line.prefix { $0 == " " || $0 == "\t" })
		var rest = Substring(line.dropFirst(leadingWhitespace.count))
		// Keep specifiers like `static`/`class`/`final`/`mutating` ahead of the inserted keyword.
		var prefixSpecifiers = ""
		let movableSpecifiers = ["static ", "class ", "final ", "mutating ", "nonmutating ", "override "]
		var changed = true
		while changed {
			changed = false
			for spec in movableSpecifiers where rest.hasPrefix(spec) {
				prefixSpecifiers += spec
				rest = rest.dropFirst(spec.count)
				changed = true
			}
		}
		guard rest.hasPrefix("func ") else { return line }
		return leadingWhitespace + prefixSpecifiers + "fileprivate " + rest
	}

	// MARK: - Batch Operations

	/**
	 Determines whether to check for empty ancestors for a given annotation and declaration kind.

	 Returns false for:
	 - Module imports (no ancestors)
	 - Superfluous ignore comments (not deleting declarations)
	 - Redundant access control (not deleting, just modifying)

	 Returns true for:
	 - Unused declarations (.unused)
	 - Other deletion cases (.assignOnlyProperty, .redundantProtocol)
	 */
	private static func shouldCheckEmptyAncestor(
		_ annotation: ScanResult.Annotation,
		_ kind: Declaration.Kind
	) -> Bool {
		if kind == .module {
			return false
		}

		switch annotation {
		case .superfluousIgnoreCommand,
		     .redundantPublicAccessibility,
		     .redundantInternalAccessibility,
		     .redundantFilePrivateAccessibility,
		     .redundantAccessibility:
			return false
		case .unused, .assignOnlyProperty, .redundantProtocol:
			return true
		}
	}

	/**
	 Holds the computed result of a batch modification without any I/O side effects.
	 Used to separate the planning phase from the execution phase in multi-file operations.
	 */
	struct BatchComputeResult {
		let removalResult: FileNode.RemovalResult
		// (afterLine, delta) pairs to apply to source graph, in computation order
		let sourceGraphAdjustments: [(afterLine: Int, delta: Int)]
	}

	/**
	 Computes all modifications for a single file without writing to disk or mutating the source graph.

	 Reads the file, applies all in-memory transformations from bottom to top, and returns the
	 planned result including the sequence of source graph line adjustments that would need to
	 be applied after writing. Callers use this to plan all files before executing any.
	 */
	static func computeBatchModifications(
		operations: [(scanResult: ScanResult, declaration: Declaration, location: Location)],
		filePath: String,
		sourceGraph: (any SourceGraphProtocol)?
	) -> Result<BatchComputeResult, Error> {
		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(CodeModificationError.cannotReadFile(filePath))
		}

		// Split contents into lines ONCE for in-memory processing
		var lines = originalContents.components(separatedBy: .newlines)
		var removedWarningIDs: [String] = []
		// Track only IDs for actual line deletions — used by shouldDeleteFile to determine
		// if declarations were physically removed (access-control fixes must NOT be included).
		var deletedWarningIDs: [String] = []
		var sourceGraphAdjustments: [(afterLine: Int, delta: Int)] = []
		var failedIgnoreCommentsCount = 0
		// Ghost modifications: access-control fixes whose rewrite produced an identical line
		// (no bytes changed). These indicate a bad source location (e.g. the Issue-12 `static let`
		// in an `actor` whose flagged line carries no modifier to rewrite). A "fix" that changes
		// nothing must NOT be counted as applied — otherwise the warning re-appears on every rescan,
		// causing an infinite cleanup loop. We collect them so the caller can surface them.
		var ghostModifications: [String] = []

		// Pre-process operations to handle preview cleanup for deleted Views
		// Use SourceGraph to find #Preview macros that reference Views being deleted
		var operationsWithPreviews: [(scanResult: ScanResult, declaration: Declaration, location: Location)] = []

		// Only run preview detection if we have a sourceGraph
		if let sourceGraph {
			// Find SwiftUI Views being deleted and their scan results
			var viewOperations: [(scanResult: ScanResult, declaration: Declaration)] = []
			for op in operations {
				let (scanResult, declaration, _) = op
				guard declaration.kind == .struct,
				      DeclarationIconHelper.conformsToView(declaration) else {
					continue
				}
				viewOperations.append((scanResult, declaration))
			}

			// Find all previews for these Views using SourceGraph
			var previewDeclarations: [Declaration] = []
			for (_, viewDecl) in viewOperations {
				let previews = PreviewDetectionHelper.findPreviewsForView(
					viewDeclaration: viewDecl,
					sourceGraph: sourceGraph
				)
				previewDeclarations.append(contentsOf: previews)
			}

			// Add original operations
			operationsWithPreviews.append(contentsOf: operations)

			// Add preview deletion operations
			// Reuse the ScanResult from the first View deletion for preview deletions
			// (The specific ScanResult doesn't matter since we're just deleting the declarations)
			if let firstViewOp = viewOperations.first, !previewDeclarations.isEmpty {
				for previewDecl in previewDeclarations {
					operationsWithPreviews.append((firstViewOp.scanResult, previewDecl, previewDecl.location))
				}
			}
		} else {
			// No source graph available, skip preview detection
			operationsWithPreviews = operations
		}

		// Collect all USRs being deleted in this batch so ancestor detection can
		// identify parents whose children are ALL being removed
		let allDeletingUSRs: Set<String> = {
			var usrs = Set<String>()
			for (_, declaration, _) in operationsWithPreviews {
				usrs.formUnion(declaration.usrs)
			}
			return usrs
		}()

		// Pre-process operations to handle empty container removal.
		// Track declarations we've already included (by USR) to avoid duplicates when
		// multiple siblings would all cause the parent to be empty.
		// When a declaration has BOTH a full-deletion annotation (.unused) and an
		// access-level annotation (e.g. .redundantPublicAccessibility), prefer the
		// full-deletion so we don't attempt to modify a line that will be deleted.
		var processedOperations: [(scanResult: ScanResult, declaration: Declaration, location: Location)] = []
		var seenUSRIndices: [String: Int] = [:] // USR → index into processedOperations

		for (scanResult, declaration, _) in operationsWithPreviews {
			// For full declaration deletions, check if parent should be deleted instead
			let actualTarget: Declaration = if shouldCheckEmptyAncestor(scanResult.annotation, declaration.kind) {
				findHighestEmptyAncestor(of: declaration, allDeletingUSRs: allDeletingUSRs, sourceGraph: sourceGraph)
			} else {
				declaration
			}

			let usr = actualTarget.usrs.first ?? ""
			if let existingIndex = seenUSRIndices[usr] {
				// Already have an operation for this USR — upgrade to full deletion if needed
				let existingAnnotation = processedOperations[existingIndex].scanResult.annotation
				let newIsDeletion = scanResult.annotation == .unused
				let existingIsDeletion = existingAnnotation == .unused
				if newIsDeletion, !existingIsDeletion {
					// Replace the access-level fix with the full deletion
					processedOperations[existingIndex] = (scanResult, actualTarget, actualTarget.location)
				}
				// Otherwise keep the existing operation (either both deletions, or existing is already deletion)
			} else {
				seenUSRIndices[usr] = processedOperations.count
				processedOperations.append((scanResult, actualTarget, actualTarget.location))
			}
		}

		// Re-sort after pre-processing: findHighestEmptyAncestor can promote operations to
		// earlier lines, breaking the bottom-to-top order established by the caller.
		// Re-sorting ensures each deletion adjusts line numbers correctly for operations above it.
		processedOperations.sort { lhs, rhs in
			if lhs.location.line != rhs.location.line {
				return lhs.location.line > rhs.location.line
			}
			return lhs.location.column > rhs.location.column
		}

		// Collect log entries during the loop; they'll be merged and emitted after post-processing
		var pendingLogEntries: [ModificationLogger.PendingEntry] = []

		// Track original line numbers alongside the lines array so post-processing
		// removals can be mapped back to original coordinates for logging
		var originalLineNumbers = Array(1 ... lines.count)

		// Track nested type names that receive `fileprivate` so we can cascade the
		// modifier to sibling inits/funcs that reference them as parameter/return types.
		// Each entry is (lineIndex: Int, typeName: String).
		var fileprivateNestedTypeNames: [(lineIndex: Int, typeName: String)] = []

		// Track type names whose `public` was removed (redundantPublicAccessibility) so we can
		// cascade-strip `public` from members declared in `extension <TypeName>` blocks in the
		// same file. Swift requires a member's declared access not exceed its extension's
		// effective access (which inherits the type's), so once the type is internal a `public`
		// member in its extension is invalid ("cannot declare a public initializer in an
		// extension with internal requirements"). Periphery flags the type but not the
		// extension member, so Treeswift must keep the rewrite self-consistent.
		var publicDowngradedTypeNames: Set<String> = []

		// Track ALL type names made `fileprivate` this batch (top-level or nested) so we can
		// cascade `fileprivate` to any `func` in the file — including extension methods and free
		// functions — whose signature references the type but carries no explicit access keyword.
		// Swift requires a function whose parameter or return type is `fileprivate` to be at most
		// `fileprivate` ("method must be declared fileprivate because its result uses a fileprivate
		// type"). The same-scope sibling cascade above does not reach extension/free functions.
		var fileprivateTypeNamesForFuncCascade: Set<String> = []

		// Track ranges deleted so far (in original line coordinates) so that
		// subsequent operations whose location.line falls inside an already-deleted
		// range are skipped rather than applied to the wrong content.
		// findDeletionStartLine can expand a deletion's start above location.line,
		// which would otherwise corrupt any lower-indexed operation that fires later.
		var deletedOriginalRanges: [(Int, Int)] = []

		// Process each operation from bottom to top so each deletion's line number
		// adjustments don't affect operations above it
		for (scanResult, declaration, location) in processedOperations {
			let usr = declaration.usrs.first ?? ""
			let warningID = "\(location.file.path.string):\(usr)"

			// Skip if this line was consumed by a prior deletion's expanded range
			if deletedOriginalRanges.contains(where: { location.line >= $0.0 && location.line <= $0.1 }) {
				continue
			}

			// Applies an access-control line rewrite, but only commits and counts it when the
			// rewrite actually changed the line. A no-op rewrite (identical line) is a ghost — the
			// flagged source location does not carry the expected modifier (e.g. Issue-12 `static
			// let` in an `actor`). Counting it would report a phantom success and re-flag forever.
			// Returns true if the line changed.
			func applyAccessControlRewrite(
				lineIndex: Int,
				newLine: String,
				action: String,
				onApplied: () -> Void = {}
			) -> Bool {
				guard lineIndex >= 0, lineIndex < lines.count else { return false }
				guard newLine != lines[lineIndex] else {
					ghostModifications
						.append("\(filePath):\(location.line) \(scanResult.annotation) — no change applied")
					return false
				}
				lines[lineIndex] = newLine
				removedWarningIDs.append(warningID)
				pendingLogEntries.append(.init(startLine: location.line, endLine: location.line, action: action))
				onApplied()
				return true
			}

			// Handle different removal types
			if case .redundantPublicAccessibility = scanResult.annotation {
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }
				let isType = declaration.kind == .struct || declaration.kind == .class
					|| declaration.kind == .enum || declaration.kind == .protocol
				_ = applyAccessControlRewrite(
					lineIndex: lineIndex,
					newLine: removeAccessKeyword("public", from: lines[lineIndex]),
					action: "removed `public`"
				) {
					// Record downgraded type names so `public` members in their extensions are
					// stripped to match (see publicDowngradedTypeNames declaration).
					if isType, !declaration.name.isEmpty {
						publicDowngradedTypeNames.insert(declaration.name)
					}
				}

			} else if case let .redundantInternalAccessibility(suggestedAccessibility) = scanResult.annotation {
				// Internal is the default, so keyword may or may not be present
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }

				if let suggested = suggestedAccessibility {
					let (modifiedLine, action) = replaceOrInsertAccessKeyword(
						oldKeyword: "internal",
						newKeyword: suggested.rawValue,
						declarationKind: declaration.kind,
						in: lines[lineIndex]
					)
					// Track nested types that become fileprivate so we can cascade
					// the modifier to sibling inits/funcs that reference them — only if applied.
					let isType = declaration.kind == .enum || declaration.kind == .struct
						|| declaration.kind == .class
					_ = applyAccessControlRewrite(lineIndex: lineIndex, newLine: modifiedLine, action: action) {
						guard isType, !declaration.name.isEmpty else { return }
						if suggested == .fileprivate, declaration.parent != nil {
							fileprivateNestedTypeNames.append((lineIndex: lineIndex, typeName: declaration.name))
						}
						// Any type narrowed to fileprivate (or file-scope private) can break
						// extension/free funcs whose signatures reference it — record for the
						// file-wide func cascade.
						if suggested == .fileprivate || suggested == .private {
							fileprivateTypeNamesForFuncCascade.insert(declaration.name)
						}
					}
				} else {
					// No suggested accessibility means top-level scope
					// Use 'private' by convention (equivalent to fileprivate at top level)
					let (modifiedLine, action) = replaceOrInsertAccessKeyword(
						oldKeyword: "internal",
						newKeyword: "private",
						declarationKind: declaration.kind,
						in: lines[lineIndex]
					)
					let isType = declaration.kind == .enum || declaration.kind == .struct
						|| declaration.kind == .class
					_ = applyAccessControlRewrite(lineIndex: lineIndex, newLine: modifiedLine, action: action) {
						if isType, !declaration.name.isEmpty {
							fileprivateTypeNamesForFuncCascade.insert(declaration.name)
						}
					}
				}

			} else if case .redundantFilePrivateAccessibility = scanResult.annotation {
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }
				_ = applyAccessControlRewrite(
					lineIndex: lineIndex,
					newLine: replaceAccessKeyword("fileprivate", with: "private", in: lines[lineIndex]),
					action: "replaced `fileprivate` with `private`"
				)

			} else if case .redundantAccessibility = scanResult.annotation {
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }
				_ = applyAccessControlRewrite(
					lineIndex: lineIndex,
					newLine: removeAnyAccessKeyword(from: lines[lineIndex]),
					action: "removed access modifier"
				)

			} else if scanResult.annotation == ScanResult.Annotation.superfluousIgnoreCommand {
				// Find and remove periphery:ignore comment
				guard let commentLine = CommentScanner.findCommentContaining(
					pattern: "periphery:ignore",
					in: lines,
					backwardFrom: location.line,
					maxDistance: 10
				) else {
					failedIgnoreCommentsCount += 1
					continue
				}

				let commentIndex = commentLine - 1
				guard commentIndex >= 0, commentIndex < lines.count else { continue }

				deletedOriginalRanges.append((commentLine, commentLine))
				lines.remove(at: commentIndex)
				originalLineNumbers.remove(at: commentIndex)
				removedWarningIDs.append(warningID)
				pendingLogEntries.append(.init(
					startLine: commentLine,
					endLine: commentLine,
					action: "removed `periphery:ignore` comment"
				))

				// Record source graph adjustment to apply after writing
				sourceGraphAdjustments.append((afterLine: commentLine, delta: -1))

			} else if declaration.kind == Declaration.Kind.module {
				// Remove import statement
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }

				deletedOriginalRanges.append((location.line, location.line))
				lines.remove(at: lineIndex)
				originalLineNumbers.remove(at: lineIndex)
				removedWarningIDs.append(warningID)
				deletedWarningIDs.append(warningID)
				pendingLogEntries.append(.init(
					startLine: location.line,
					endLine: location.line,
					action: "Deleted import"
				))

				// Record source graph adjustment to apply after writing
				sourceGraphAdjustments.append((afterLine: location.line, delta: -1))

			} else {
				// Delete full declaration (struct, property, function, etc.)

				// Special handling for enum cases on the same line as other cases
				if declaration.kind == .enumelement {
					let caseName = declaration.name
					if !caseName.isEmpty,
					   let modifiedLines = DeclarationDeletionHelper.handleInlineEnumCaseDeletion(
					   	lines: lines,
					   	declarationLine: location.line,
					   	caseName: caseName
					   ) {
						// Successfully handled inline case deletion
						lines = modifiedLines
						removedWarningIDs.append(warningID)
						deletedWarningIDs.append(warningID)
						pendingLogEntries.append(.init(
							startLine: location.line,
							endLine: location.line,
							action: "removed enum case `\(caseName)`"
						))
						// No line number adjustments needed - we only modified one line
						continue
					}
				}

				guard let endLine = location.endLine else { continue }

				// Find actual start line (including attributes and comments)
				let startLine = DeclarationDeletionHelper.findDeletionStartLine(
					lines: lines,
					declarationLine: location.line,
					attributes: declaration.attributes
				)

				// Determine ending line (includes smart blank line handling)
				var finalStartLine = startLine
				var finalEndLine = DeclarationDeletionHelper.findDeletionEndLine(
					lines: lines,
					declarationLine: location.line,
					declarationEndLine: endLine
				)

				// Check if we're inside an empty #if block
				if let adjustedRange = DeclarationDeletionHelper.checkForEmptyConditionalBlock(
					lines: lines,
					startLine: finalStartLine,
					endLine: finalEndLine
				) {
					finalStartLine = adjustedRange.newStartLine
					finalEndLine = adjustedRange.newEndLine
				}

				// Validate range
				let startIndex = finalStartLine - 1
				let endIndex = finalEndLine - 1
				guard startIndex >= 0, endIndex < lines.count, startIndex <= endIndex else {
					continue
				}

				// Record expanded deletion range so later operations landing inside it are skipped
				deletedOriginalRanges.append((finalStartLine, finalEndLine))

				// Remove lines from array
				let linesRemoved = endIndex - startIndex + 1
				lines.removeSubrange(startIndex ... endIndex)
				originalLineNumbers.removeSubrange(startIndex ... endIndex)
				removedWarningIDs.append(warningID)
				deletedWarningIDs.append(warningID)
				pendingLogEntries.append(.init(startLine: finalStartLine, endLine: finalEndLine, action: "Deleted"))

				// Record source graph adjustment to apply after writing
				sourceGraphAdjustments.append((afterLine: finalEndLine, delta: -linesRemoved))
			}
		}

		// Cascade `fileprivate` to sibling inits/funcs whose parameter/return types just
		// became fileprivate. Swift requires the containing declaration to also be fileprivate
		// when its signature references a fileprivate type. We handle this by scanning the
		// lines within the enclosing type body for `init` or `func` declarations that:
		//   1. reference the newly-fileprivate type name in their parameter list or return type
		//   2. do not yet carry an explicit access modifier
		//
		// We detect the enclosing scope by counting braces from the fileprivate type's line
		// backwards to find the opening `{` of the parent type, then forward to find its
		// closing `}`. Within that range we patch any unguarded init/func that uses the type.
		if !fileprivateNestedTypeNames.isEmpty {
			lines = Self.cascadeFileprivateToAffectedDeclarations(
				lines: lines,
				fileprivateNestedTypeNames: fileprivateNestedTypeNames,
				pendingLogEntries: &pendingLogEntries
			)
		}

		// A type whose `public` was just removed makes `public` members in its extensions
		// invalid. Strip `public` from declarations inside `extension <TypeName>` blocks so the
		// rewrite stays self-consistent (see publicDowngradedTypeNames declaration).
		if !publicDowngradedTypeNames.isEmpty {
			lines = Self.cascadePublicStripFromExtensions(
				lines: lines,
				downgradedTypeNames: publicDowngradedTypeNames,
				pendingLogEntries: &pendingLogEntries
			)
		}

		// A `func` (extension method or free function) whose signature references a type just
		// narrowed to fileprivate must itself be at most fileprivate. The same-scope sibling
		// cascade above does not reach extension/free functions, so do a file-wide pass.
		if !fileprivateTypeNamesForFuncCascade.isEmpty {
			lines = Self.cascadeFileprivateToReferencingFunctions(
				lines: lines,
				fileprivateTypeNames: fileprivateTypeNamesForFuncCascade,
				pendingLogEntries: &pendingLogEntries
			)
		}

		// Snapshot before post-processing so we can detect which lines were removed
		let linesBeforePostProcessing = lines

		// Remove empty containers (extensions, classes, etc.) left behind after deletions
		lines = DeclarationDeletionHelper.removeEmptyContainers(from: lines)

		// Remove orphaned MARK/TODO/FIXME comments left behind after deletions
		lines = DeclarationDeletionHelper.removeOrphanedSectionMarkers(from: lines)

		// Collapse consecutive blank lines left behind by multiple deletions
		lines = DeclarationDeletionHelper.collapseConsecutiveBlankLines(in: lines)

		// Find lines removed by post-processing and add them as pending deletion entries.
		// Post-processing only removes lines (no reordering), so we can walk both arrays
		// with two pointers to find which indices were removed.
		if ModificationLogger.isEnabled, lines.count < linesBeforePostProcessing.count {
			var removedIndices: [Int] = []
			var newIdx = 0
			for oldIdx in linesBeforePostProcessing.indices {
				if newIdx < lines.count, lines[newIdx] == linesBeforePostProcessing[oldIdx] {
					newIdx += 1
				} else {
					removedIndices.append(oldIdx)
				}
			}
			for oldIdx in removedIndices {
				let origLine = originalLineNumbers[oldIdx]
				pendingLogEntries.append(.init(startLine: origLine, endLine: origLine, action: "Deleted"))
			}
		}

		// Emit all collected log entries (merging contiguous deletions)
		ModificationLogger.emitPendingEntries(pendingLogEntries, filePath: filePath)

		// Join lines back into string
		let currentContents = lines.joined(separator: "\n")

		// Determine if file should be deleted or if imports should be removed
		var shouldDeleteFile = false
		var shouldRemoveImports = false
		var finalContents = currentContents

		if let graph = sourceGraph {
			let analysisResult = FileContentAnalyzer.shouldDeleteFile(
				filePath: filePath,
				modifiedContents: currentContents,
				sourceGraph: graph,
				removedWarningIDs: deletedWarningIDs
			)
			shouldDeleteFile = analysisResult.shouldDelete
			shouldRemoveImports = analysisResult.shouldRemoveImports

			// If keeping file only for comments, remove imports
			if shouldRemoveImports {
				finalContents = FileContentAnalyzer.removeImportStatements(from: currentContents)
			}
		}

		// Count total and non-deletable warnings (caller provides these via operations list)
		let deletedCount = removedWarningIDs.count
		let nonDeletableCount = 0 // Caller pre-filters, so all were deletable

		let removalResult = FileNode.RemovalResult(
			filePath: filePath,
			originalContents: originalContents,
			modifiedContents: finalContents,
			removedWarningIDs: removedWarningIDs,
			adjustedUSRs: [],
			shouldDeleteFile: shouldDeleteFile,
			shouldRemoveImports: shouldRemoveImports,
			deletionStats: FileNode.DeletionStats(
				deletedCount: deletedCount,
				nonDeletableCount: nonDeletableCount,
				failedIgnoreCommentsCount: failedIgnoreCommentsCount,
				skippedReferencedCount: 0,
				ghostModifications: ghostModifications
			)
		)
		return .success(BatchComputeResult(
			removalResult: removalResult,
			sourceGraphAdjustments: sourceGraphAdjustments
		))
	}
}
