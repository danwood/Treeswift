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

	// MARK: - Empty Container Detection

	/**
	 Finds the highest ancestor container that would become empty after deleting the given declaration.

	 Walks up the parent chain to find containers that have only one child (the declaration being deleted,
	 or its ancestor). Returns the highest such ancestor, or the original declaration if no parents would be empty.

	 Example:
	 ```
	 extension Foo {
	     struct Bar {
	         var unused: Int  // Only member
	     }
	 }
	 ```
	 When deleting `unused`, this returns the `extension Foo` declaration since both `Bar` and the extension
	 would become empty.
	 */
	private static func findHighestEmptyAncestor(of declaration: Declaration) -> Declaration {
		var current = declaration

		while let parent = current.parent,
		      parent.declarations.count == 1 {
			// Parent would be empty after removing current
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
	 Replaces or inserts an access keyword in a line.
	 If the old keyword exists, replaces it. Otherwise inserts the new keyword.
	 */
	private static func replaceOrInsertAccessKeyword(
		oldKeyword: String?,
		newKeyword: String,
		declarationKind: Declaration.Kind,
		in line: String
	) -> String {
		if let oldKeyword,
		   let pattern = try? Regex("\\b\(oldKeyword)\\s+"),
		   line.contains(pattern) {
			replaceAccessKeyword(oldKeyword, with: newKeyword, in: line)
		} else {
			insertAccessKeyword(newKeyword, before: declarationKind, in: line)
		}
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
			// Remove any explicit 'internal' keyword before inserting 'private'
			let lineWithoutInternal = removeAccessKeyword("internal", from: originalLine)
			newLine = insertAccessKeyword("private", before: declaration.kind, in: lineWithoutInternal)

		case .insertFilePrivate:
			// Remove any explicit 'internal' keyword before inserting 'fileprivate'
			let lineWithoutInternal = removeAccessKeyword("internal", from: originalLine)
			newLine = insertAccessKeyword("fileprivate", before: declaration.kind, in: lineWithoutInternal)
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

		// Find the declaration keyword and insert access keyword before it
		if let range = line.range(of: declarationKeyword) {
			return line.replacingCharacters(in: range, with: "\(keyword) \(declarationKeyword)")
		}

		// Fallback: insert at beginning of trimmed line
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		let leadingWhitespace = String(line.prefix(while: { $0.isWhitespace }))
		return leadingWhitespace + keyword + " " + trimmed
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
		sourceGraph: SourceGraph?,
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
			let caseName = declaration.name ?? ""
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
		let actualTarget = findHighestEmptyAncestor(of: declaration)

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
			declarationLine: startLine,
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
		sourceGraph: SourceGraph?,
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
		sourceGraph: SourceGraph?,
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
		sourceGraph: SourceGraph?,
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
	 Executes multiple modifications on a single file in a single operation.

	 Reads the file once, applies all modifications in-memory from bottom to top,
	 then writes once. This is more efficient than individual operations and ensures
	 atomicity of the batch.

	 Note: This method does NOT register undo/redo - that's the caller's responsibility.
	 The caller receives detailed results and can register a batch undo operation.
	 */
	static func executeBatchModifications(
		operations: [(scanResult: ScanResult, declaration: Declaration, location: Location)],
		filePath: String,
		sourceGraph: SourceGraph?
	) -> Result<FileNode.RemovalResult, Error> {
		// Read original file contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return .failure(CodeModificationError.cannotReadFile(filePath))
		}

		// Split contents into lines ONCE for in-memory processing
		var lines = originalContents.components(separatedBy: .newlines)
		var removedWarningIDs: [String] = []
		var adjustedUSRs: [String] = []
		var failedIgnoreCommentsCount = 0

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

		// Pre-process operations to handle empty container removal
		// Track declarations we've already included (by USR) to avoid duplicates when
		// multiple siblings would all cause the parent to be empty
		var processedOperations: [(scanResult: ScanResult, declaration: Declaration, location: Location)] = []
		var seenUSRs = Set<String>()

		for (scanResult, declaration, _) in operationsWithPreviews {
			// For full declaration deletions, check if parent should be deleted instead
			let actualTarget: Declaration = if shouldCheckEmptyAncestor(scanResult.annotation, declaration.kind) {
				findHighestEmptyAncestor(of: declaration)
			} else {
				declaration
			}

			// Skip if we've already added this declaration (or its ancestor)
			let usr = actualTarget.usrs.first ?? ""
			if !seenUSRs.contains(usr) {
				seenUSRs.insert(usr)
				processedOperations.append((scanResult, actualTarget, actualTarget.location))
			}
		}

		// Process each operation from bottom to top
		// Since sorted bottom-to-top, each deletion automatically shifts remaining correctly
		for (scanResult, declaration, location) in processedOperations {
			let usr = declaration.usrs.first ?? ""
			let warningID = "\(location.file.path.string):\(usr)"

			// Handle different removal types
			if case .redundantPublicAccessibility = scanResult.annotation {
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }
				lines[lineIndex] = removeAccessKeyword("public", from: lines[lineIndex])
				removedWarningIDs.append(warningID)

			} else if case let .redundantInternalAccessibility(_, suggestedAccessibility) = scanResult.annotation {
				// Internal is the default, so keyword may or may not be present
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }

				if let suggested = suggestedAccessibility {
					lines[lineIndex] = replaceOrInsertAccessKeyword(
						oldKeyword: "internal",
						newKeyword: suggested.rawValue,
						declarationKind: declaration.kind,
						in: lines[lineIndex]
					)
				} else {
					// No suggested accessibility means top-level scope
					// Use 'private' by convention (equivalent to fileprivate at top level)
					lines[lineIndex] = replaceOrInsertAccessKeyword(
						oldKeyword: "internal",
						newKeyword: "private",
						declarationKind: declaration.kind,
						in: lines[lineIndex]
					)
				}
				removedWarningIDs.append(warningID)

			} else if case .redundantFilePrivateAccessibility = scanResult.annotation {
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }
				lines[lineIndex] = replaceAccessKeyword("fileprivate", with: "private", in: lines[lineIndex])
				removedWarningIDs.append(warningID)

			} else if case .redundantAccessibility = scanResult.annotation {
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }
				lines[lineIndex] = removeAnyAccessKeyword(from: lines[lineIndex])
				removedWarningIDs.append(warningID)

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

				lines.remove(at: commentIndex)
				removedWarningIDs.append(warningID)

				// Adjust source graph line numbers
				if let sourceGraph {
					let adjusted = SourceGraphLineAdjuster.adjustAndTrack(
						sourceGraph: sourceGraph,
						filePath: filePath,
						afterLine: commentLine,
						lineDelta: -1
					)
					adjustedUSRs.append(contentsOf: adjusted)
				}

			} else if declaration.kind == Declaration.Kind.module {
				// Remove import statement
				let lineIndex = location.line - 1
				guard lineIndex >= 0, lineIndex < lines.count else { continue }

				lines.remove(at: lineIndex)
				removedWarningIDs.append(warningID)

				// Adjust source graph
				if let sourceGraph {
					let adjusted = SourceGraphLineAdjuster.adjustAndTrack(
						sourceGraph: sourceGraph,
						filePath: filePath,
						afterLine: location.line,
						lineDelta: -1
					)
					adjustedUSRs.append(contentsOf: adjusted)
				}

			} else {
				// Delete full declaration (struct, property, function, etc.)

				// Special handling for enum cases on the same line as other cases
				if declaration.kind == .enumelement {
					let caseName = declaration.name ?? ""
					if !caseName.isEmpty,
					   let modifiedLines = DeclarationDeletionHelper.handleInlineEnumCaseDeletion(
					   	lines: lines,
					   	declarationLine: location.line,
					   	caseName: caseName
					   ) {
						// Successfully handled inline case deletion
						lines = modifiedLines
						removedWarningIDs.append(warningID)
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
					declarationLine: startLine,
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

				// Remove lines from array
				let linesRemoved = endIndex - startIndex + 1
				lines.removeSubrange(startIndex ... endIndex)
				removedWarningIDs.append(warningID)

				// Adjust source graph
				if let sourceGraph {
					let adjusted = SourceGraphLineAdjuster.adjustAndTrack(
						sourceGraph: sourceGraph,
						filePath: filePath,
						afterLine: finalEndLine,
						lineDelta: -linesRemoved
					)
					adjustedUSRs.append(contentsOf: adjusted)
				}
			}
		}

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
				removedWarningIDs: removedWarningIDs
			)
			shouldDeleteFile = analysisResult.shouldDelete
			shouldRemoveImports = analysisResult.shouldRemoveImports

			// If keeping file only for comments, remove imports
			if shouldRemoveImports {
				finalContents = FileContentAnalyzer.removeImportStatements(from: currentContents)
			}
		}

		// Write modified contents to file
		do {
			try finalContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			return .failure(CodeModificationError.cannotWriteFile(filePath))
		}

		// Invalidate cache
		SourceFileReader.invalidateCache(for: filePath)

		// Count total and non-deletable warnings (caller provides these via operations list)
		let deletedCount = removedWarningIDs.count
		let nonDeletableCount = 0 // Caller pre-filters, so all were deletable

		return .success(FileNode.RemovalResult(
			filePath: filePath,
			originalContents: originalContents,
			modifiedContents: finalContents,
			removedWarningIDs: removedWarningIDs,
			adjustedUSRs: adjustedUSRs,
			shouldDeleteFile: shouldDeleteFile,
			shouldRemoveImports: shouldRemoveImports,
			deletionStats: FileNode.DeletionStats(
				deletedCount: deletedCount,
				nonDeletableCount: nonDeletableCount,
				failedIgnoreCommentsCount: failedIgnoreCommentsCount
			)
		))
	}
}
