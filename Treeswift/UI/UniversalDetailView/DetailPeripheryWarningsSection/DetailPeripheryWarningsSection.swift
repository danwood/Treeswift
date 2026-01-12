//
//  DetailPeripheryWarningsSection.swift
//  Treeswift
//
//  Detail section showing Periphery scan warnings for a file
//

import SwiftUI
import PeripheryKit
import SourceGraph
import SystemPackage

struct DetailPeripheryWarningsSection: View {
	let filePath: String
	let scanResults: [ScanResult]
	let sourceGraph: SourceGraph?
	let filterState: FilterState?

	@AppStorage("showPeripheryWarningDetails") private var showDetails: Bool = false
	@State private var expandedWarnings: Set<String> = []
	@State private var completedActions: Set<String> = []
	@State private var refreshTrigger: Int = 0
	@State private var removingWarnings: Set<String> = []
	@State private var ignoringWarnings: Set<String> = []

	// Initialize with optional filter state
	init(
		filePath: String,
		scanResults: [ScanResult],
		sourceGraph: SourceGraph? = nil,
		filterState: FilterState? = nil
	) {
		self.filePath = filePath
		self.scanResults = scanResults
		self.sourceGraph = sourceGraph
		self.filterState = filterState
	}

	// Filter warnings for this specific file and sort by line:column
	private var fileWarnings: [(result: ScanResult, declaration: Declaration)] {
		scanResults
			.compactMap { result -> (result: ScanResult, declaration: Declaration)? in
				let declaration = result.declaration
				let location = ScanResultHelper.location(from: declaration)

				// Match file path
				guard location.file.path.string == filePath else { return nil }

				// Apply filter state if provided
				if let filterState = filterState {
					guard filterState.shouldShow(result: result, declaration: declaration) else {
						return nil
					}
				}

				return (result, declaration)
			}
			.sorted { lhs, rhs in
				// Sort by line number, then column number for logical reading order
				let lhsLocation = ScanResultHelper.location(from: lhs.declaration)
				let rhsLocation = ScanResultHelper.location(from: rhs.declaration)
				if lhsLocation.line != rhsLocation.line {
					return lhsLocation.line < rhsLocation.line
				}
				return lhsLocation.column < rhsLocation.column
			}
	}

	var body: some View {
		if !fileWarnings.isEmpty {
			VStack(alignment: .leading, spacing: 12) {
				DynamicStack(spacing: 8) {
					Text("Periphery Warnings")
						.font(.headline)
					Spacer()
					Toggle("Show Details", isOn: Binding(
						get: { showDetails },
						set: { newValue in
							withAnimation(.easeInOut(duration: 0.2)) {
								showDetails = newValue
							}
						}
					))
					.toggleStyle(.switch)
					.controlSize(.small)
				}

				Grid(alignment: .topLeading, horizontalSpacing: 4, verticalSpacing: 4) {
					ForEach(Array(fileWarnings.enumerated()), id: \.offset) { _, tuple in
						PeripheryWarningRow(
							result: tuple.result,
							declaration: tuple.declaration,
							showDetails: showDetails,
							sourceGraph: sourceGraph,
							expandedWarnings: $expandedWarnings,
							completedActions: $completedActions,
							refreshTrigger: $refreshTrigger,
							removingWarnings: $removingWarnings,
							ignoringWarnings: $ignoringWarnings
						)
					}
				}
				.id(refreshTrigger)
			}
			.padding(.vertical, 4)
			.onReceive(NotificationCenter.default.publisher(for: Notification.Name("PeripheryWarningRestored"))) { notification in
				// Remove specific warning from completed actions
				if let warningID = notification.object as? String {
					completedActions.remove(warningID)
					refreshTrigger += 1
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: Notification.Name("PeripheryWarningCompleted"))) { notification in
				// Add specific warning to completed actions
				if let warningID = notification.object as? String {
					completedActions.insert(warningID)
					refreshTrigger += 1
				}
			}
		}
	}
}

// Individual warning row with clickable badge and selectable text - shared component
struct PeripheryWarningRow: View {
	let result: ScanResult
	let declaration: Declaration
	let showDetails: Bool
	let sourceGraph: SourceGraph?
	@Binding var expandedWarnings: Set<String>
	@Binding var completedActions: Set<String>
	@Binding var refreshTrigger: Int
	@Binding var removingWarnings: Set<String>
	@Binding var ignoringWarnings: Set<String>
	@Environment(\.undoManager) private var undoManager

	// Read location from declaration so it updates when declaration.location changes
	private var location: Location {
		ScanResultHelper.location(from: declaration)
	}

	private var badge: Badge {
		let swiftType = SwiftType.from(declarationKind: declaration.kind)

		return Badge(
			letter: swiftType.rawValue,
			count: 1,
			swiftType: swiftType,
			isUnused: result.annotation.isUnused
		)
	}

	private var warningText: AttributedString {
		return ScanResultHelper.formatAttributedDescription(
			declaration: declaration,
			annotation: result.annotation
		)
	}

	private var sourceLine: AttributedString? {
		guard showDetails else { return nil }

		guard let lineText = SourceFileReader.readLine(
			from: location.file.path.string,
			lineNumber: location.line
		) else {
			return nil
		}

		// Check if deletion starts before the declaration line (has attributes above)
		let filePath = location.file.path.string
		if let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) {
			let lines = fileContents.components(separatedBy: .newlines)
			let startLine = DeclarationDeletionHelper.findDeletionStartLine(
				lines: lines,
				declarationLine: location.line,
				attributes: declaration.attributes
			)

			// If deletion starts before declaration line, check for @ modifiers
			if startLine < location.line {
				// Look for @ modifiers in the lines before the declaration
				for lineNum in startLine..<location.line {
					let lineIndex = lineNum - 1
					guard lineIndex >= 0 && lineIndex < lines.count else { continue }
					let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)

					// Find @ modifier
					if let atIndex = line.firstIndex(of: "@") {
						let afterAt = line[line.index(after: atIndex)...]
						// Extract modifier name (stop at parenthesis or whitespace)
						let modifierName = afterAt.prefix(while: { $0 != "(" && !$0.isWhitespace })
						if !modifierName.isEmpty {
							// Format as "@ModifierName… <declaration line>"
							let trimmedDeclaration = lineText.trimmingCharacters(in: .whitespaces)
							let combinedText = "@\(modifierName)… \(trimmedDeclaration)"
							return ScanResultHelper.highlightSymbolInSourceLine(
								line: combinedText,
								column: location.column + combinedText.count - trimmedDeclaration.count,
								symbolName: declaration.name
							)
						}
					}
				}
			}
		}

		// For redundant public warnings, highlight the "public " keyword instead of the symbol
		if isRedundantPublic {
			return ScanResultHelper.highlightRedundantPublicInLine(line: lineText)
		}

		return ScanResultHelper.highlightSymbolInSourceLine(
			line: lineText,
			column: location.column,
			symbolName: declaration.name
		)
	}

	// Generate unique ID for this warning using stable USR
	private var warningID: String {
		let usr = declaration.usrs.first ?? ""
		return "\(location.file.path.string):\(usr)"
	}


	// Check if annotation is redundant public
	private var isRedundantPublic: Bool {
		if case ScanResult.Annotation.redundantPublicAccessibility = result.annotation { true } else { false }
	}

	// Check if annotation is redundant protocol
	private var isRedundantProtocol: Bool {
		if case ScanResult.Annotation.redundantProtocol = result.annotation { true } else { false }
	}

	// Check if location has full range info for deletion
	private var hasFullRange: Bool {
		location.endLine != nil && location.endColumn != nil
	}

	// Check if this is an import declaration
	private var isImport: Bool {
		declaration.kind == .module
	}

	// Check if declaration can be deleted (has full range or is import)
	private var canDelete: Bool {
		hasFullRange || isImport
	}

	// Check if an action is available for this warning type
	// Check if source preview has multiple lines (including attributes)
	private var hasMultiLineSource: Bool {
		guard let endLine = location.endLine else { return false }

		// Multi-line if the declaration itself spans multiple lines
		if endLine > location.line {
			return true
		}

		// Check actual source code for attribute lines before the declaration
		let filePath = location.file.path.string
		guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return false
		}
		let lines = fileContents.components(separatedBy: .newlines)

		let startLine = DeclarationDeletionHelper.findDeletionStartLine(
			lines: lines,
			declarationLine: location.line,
			attributes: declaration.attributes
		)

		// Multi-line if attributes start before the declaration line
		let result = startLine < location.line
		return result
	}

	// Load source code preview for a declaration
	private func loadSourcePreview() -> String? {
		guard let endLine = location.endLine else { return nil }

		let filePath = location.file.path.string
		guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }

		let lines = fileContents.components(separatedBy: .newlines)
		guard location.line > 0 && location.line <= lines.count else { return nil }
		guard endLine > 0 && endLine <= lines.count else { return nil }

		// Find actual start line including attributes and comments
		let startLine = DeclarationDeletionHelper.findDeletionStartLine(
			lines: lines,
			declarationLine: location.line,
			attributes: declaration.attributes
		)

		let startIndex = startLine - 1
		let endIndex = endLine - 1
		let relevantLines = lines[startIndex...endIndex]

		return relevantLines.joined(separator: "\n")
	}

	// Delete declaration from source file
	private func deleteDeclaration() {
		// Start fade-out animation
		_ = withAnimation(.easeInOut(duration: 0.3)) {
			removingWarnings.insert(warningID)
		}

		// Delay for animation, then delete
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(300))

			// Special case for imports (single line deletion)
			if isImport {
				deleteImportStatementImpl()
				return
			}

			// Use enhanced deletion with sourceGraph if available
			if let sourceGraph = self.sourceGraph, hasFullRange {
				deleteDeclarationImpl(sourceGraph: sourceGraph)
			} else {
				// Fallback to simple deletion when sourceGraph is missing
				simpleDeleteDeclarationImpl()
			}
		}
	}

	// Implementation of delete declaration (extracted from deleteDeclaration)
	private func deleteDeclarationImpl(sourceGraph: SourceGraph) {
		let filePath = location.file.path.string
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

		// Use helper for smart deletion
		let result = DeclarationDeletionHelper.deleteDeclaration(declaration: declaration)

		switch result {
		case .success(let deletionRange):
				// Invalidate source file cache so preview shows updated content
				SourceFileReader.invalidateCache(for: filePath)

				// Adjust line numbers and track which declarations were adjusted
				let linesRemoved = deletionRange.endLine - deletionRange.startLine + 1
				let afterLine = deletionRange.endLine
				var adjustedUSRs: [String] = []

				for declaration in sourceGraph.allDeclarations {
					guard declaration.location.file.path.string == filePath else { continue }
					guard declaration.location.line > afterLine else { continue }

					let newLine = declaration.location.line - linesRemoved
					let newEndLine = declaration.location.endLine.map { $0 - linesRemoved }
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

				// Get modified contents after deletion
				guard let modifiedContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

				// Register undo with closure-based redo support
				if let undoManager = undoManager {
					let capturedOriginal = originalContents
					let capturedModified = modifiedContents
					let capturedPath = filePath
					let capturedWarningID = warningID
					let capturedAdjustedUSRs = adjustedUSRs
					let capturedLineAdjustment = linesRemoved

					// Define the undo action
					@MainActor
			func performUndo() {
						try? capturedOriginal.write(toFile: capturedPath, atomically: true, encoding: .utf8)
						SourceFileReader.invalidateCache(for: capturedPath)

						// Reverse line number adjustments
						for declaration in sourceGraph.allDeclarations {
							guard declaration.location.file.path.string == capturedPath else { continue }
							guard let declUSR = declaration.usrs.first else { continue }
							guard capturedAdjustedUSRs.contains(declUSR) else { continue }

							let newLine = declaration.location.line + capturedLineAdjustment
							let newEndLine = declaration.location.endLine.map { $0 + capturedLineAdjustment }
							declaration.location = Location(
								file: declaration.location.file,
								line: newLine,
								column: declaration.location.column,
								endLine: newEndLine,
								endColumn: declaration.location.endColumn
							)
						}


					// Remove from removal state
					removingWarnings.remove(capturedWarningID)
						NotificationCenter.default.post(
							name: Notification.Name("PeripheryWarningRestored"),
							object: capturedWarningID
						)

						// Register redo
						undoManager.registerUndo(withTarget: NSObject()) { _ in
							performRedo()
						}
						undoManager.setActionName("Delete Declaration")
					}

					// Define the redo action
					@MainActor
			func performRedo() {
						try? capturedModified.write(toFile: capturedPath, atomically: true, encoding: .utf8)
						SourceFileReader.invalidateCache(for: capturedPath)

						// Reapply line number adjustments
						for declaration in sourceGraph.allDeclarations {
							guard declaration.location.file.path.string == capturedPath else { continue }
							guard let declUSR = declaration.usrs.first else { continue }
							guard capturedAdjustedUSRs.contains(declUSR) else { continue }

							let newLine = declaration.location.line - capturedLineAdjustment
							let newEndLine = declaration.location.endLine.map { $0 - capturedLineAdjustment }
							declaration.location = Location(
								file: declaration.location.file,
								line: newLine,
								column: declaration.location.column,
								endLine: newEndLine,
								endColumn: declaration.location.endColumn
							)
						}

					// Mark as removed again
					removingWarnings.insert(capturedWarningID)

						NotificationCenter.default.post(
							name: Notification.Name("PeripheryWarningCompleted"),
							object: capturedWarningID
						)

						// Register undo
						undoManager.registerUndo(withTarget: NSObject()) { _ in
							performUndo()
						}
						undoManager.setActionName("Delete Declaration")
					}

					// Register initial undo
					undoManager.registerUndo(withTarget: NSObject()) { _ in
						performUndo()
					}
					undoManager.setActionName("Delete Declaration")
				}

				// Mark action as completed
				completedActions.insert(warningID)
				removingWarnings.remove(warningID)

				// Notify that warning was completed
				NotificationCenter.default.post(
					name: Notification.Name("PeripheryWarningCompleted"),
					object: warningID
				)
			case .failure(let error):
				print("Deletion failed: \(error.localizedDescription)")
			}
	}

	// Simple deletion without smart boundary detection
	private func simpleDeleteDeclarationImpl() {
		guard let endLine = location.endLine, let _ = location.endColumn else { return }

		let filePath = location.file.path.string
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

		// Delete the declaration range
		var lines = originalContents.components(separatedBy: .newlines)
		guard location.line > 0 && location.line <= lines.count else { return }
		guard endLine > 0 && endLine <= lines.count else { return }

		// Remove lines from startLine to endLine (inclusive)
		let startIndex = location.line - 1
		let endIndex = endLine - 1
		lines.removeSubrange(startIndex...endIndex)

		// Write back to file
		let newContents = lines.joined(separator: "\n")
		try? newContents.write(toFile: filePath, atomically: true, encoding: .utf8)

		// Invalidate source file cache so preview shows updated content
		SourceFileReader.invalidateCache(for: filePath)

		// Adjust line numbers and track which declarations were adjusted
		let linesRemoved = endLine - location.line + 1
		let afterLine = endLine
		var adjustedUSRs: [String] = []

		if let sourceGraph = sourceGraph {
			for declaration in sourceGraph.allDeclarations {
				guard declaration.location.file.path.string == filePath else { continue }
				guard declaration.location.line > afterLine else { continue }

				let newLine = declaration.location.line - linesRemoved
				let newEndLine = declaration.location.endLine.map { $0 - linesRemoved }
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
		}

		// Register undo with closure-based redo support
		if let undoManager = undoManager {
			let capturedOriginal = originalContents
			let capturedModified = newContents
			let capturedPath = filePath
			let capturedWarningID = warningID
			let capturedAdjustedUSRs = adjustedUSRs
			let capturedLineAdjustment = linesRemoved
			let capturedSourceGraph = sourceGraph

			// Define the undo action
			@MainActor
			func performUndo() {
				try? capturedOriginal.write(toFile: capturedPath, atomically: true, encoding: .utf8)
				SourceFileReader.invalidateCache(for: capturedPath)

				// Reverse line number adjustments
				if let sourceGraph = capturedSourceGraph {
					for declaration in sourceGraph.allDeclarations {
						guard declaration.location.file.path.string == capturedPath else { continue }
						guard let declUSR = declaration.usrs.first else { continue }
						guard capturedAdjustedUSRs.contains(declUSR) else { continue }

						let newLine = declaration.location.line + capturedLineAdjustment
						let newEndLine = declaration.location.endLine.map { $0 + capturedLineAdjustment }
						declaration.location = Location(
							file: declaration.location.file,
							line: newLine,
							column: declaration.location.column,
							endLine: newEndLine,
							endColumn: declaration.location.endColumn
						)
					}
				}

				NotificationCenter.default.post(
					name: Notification.Name("PeripheryWarningRestored"),
					object: capturedWarningID
				)

				// Register redo
				undoManager.registerUndo(withTarget: NSObject()) { _ in
					performRedo()
				}
				undoManager.setActionName("Delete Declaration")
			}

			// Define the redo action
			@MainActor
			func performRedo() {
				try? capturedModified.write(toFile: capturedPath, atomically: true, encoding: .utf8)
				SourceFileReader.invalidateCache(for: capturedPath)

				// Reapply line number adjustments
				if let sourceGraph = capturedSourceGraph {
					for declaration in sourceGraph.allDeclarations {
						guard declaration.location.file.path.string == capturedPath else { continue }
						guard let declUSR = declaration.usrs.first else { continue }
						guard capturedAdjustedUSRs.contains(declUSR) else { continue }

						let newLine = declaration.location.line - capturedLineAdjustment
						let newEndLine = declaration.location.endLine.map { $0 - capturedLineAdjustment }
						declaration.location = Location(
							file: declaration.location.file,
							line: newLine,
							column: declaration.location.column,
							endLine: newEndLine,
							endColumn: declaration.location.endColumn
						)
					}
				}

				NotificationCenter.default.post(
					name: Notification.Name("PeripheryWarningCompleted"),
					object: capturedWarningID
				)

				// Register undo
				undoManager.registerUndo(withTarget: NSObject()) { _ in
					performUndo()
				}
				undoManager.setActionName("Delete Declaration")
			}

			// Register initial undo
			undoManager.registerUndo(withTarget: NSObject()) { _ in
				performUndo()
			}
			undoManager.setActionName("Delete Declaration")
		}

		// Mark action as completed
		completedActions.insert(warningID)
		removingWarnings.remove(warningID)

		// Notify that warning was completed
		NotificationCenter.default.post(
			name: Notification.Name("PeripheryWarningCompleted"),
			object: warningID
		)
	}

	// Delete import statement (single line only)
	private func deleteImportStatementImpl() {
		let filePath = location.file.path.string
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

		// Delete the single import line
		var lines = originalContents.components(separatedBy: .newlines)
		guard location.line > 0 && location.line <= lines.count else { return }

		// Remove the import line
		let lineIndex = location.line - 1
		lines.remove(at: lineIndex)

		// Write back to file
		let newContents = lines.joined(separator: "\n")
		try? newContents.write(toFile: filePath, atomically: true, encoding: .utf8)

		// Invalidate source file cache so preview shows updated content
		SourceFileReader.invalidateCache(for: filePath)

		// Adjust line numbers and track which declarations were adjusted
		let afterLine = location.line
		var adjustedUSRs: [String] = []

		if let sourceGraph = sourceGraph {
			for declaration in sourceGraph.allDeclarations {
				guard declaration.location.file.path.string == filePath else { continue }
				guard declaration.location.line > afterLine else { continue }

				let newLine = declaration.location.line - 1
				let newEndLine = declaration.location.endLine.map { $0 - 1 }
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
		}

		// Register undo with closure-based redo support
		if let undoManager = undoManager {
			let capturedOriginal = originalContents
			let capturedModified = newContents
			let capturedPath = filePath
			let capturedWarningID = warningID
			let capturedAdjustedUSRs = adjustedUSRs
			let capturedLineAdjustment = 1
			let capturedSourceGraph = sourceGraph

			// Define the undo action
			@MainActor
			func performUndo() {
				try? capturedOriginal.write(toFile: capturedPath, atomically: true, encoding: .utf8)
				SourceFileReader.invalidateCache(for: capturedPath)

				// Reverse line number adjustments
				if let sourceGraph = capturedSourceGraph {
					for declaration in sourceGraph.allDeclarations {
						guard declaration.location.file.path.string == capturedPath else { continue }
						guard let declUSR = declaration.usrs.first else { continue }
						guard capturedAdjustedUSRs.contains(declUSR) else { continue }

						let newLine = declaration.location.line + capturedLineAdjustment
						let newEndLine = declaration.location.endLine.map { $0 + capturedLineAdjustment }
						declaration.location = Location(
							file: declaration.location.file,
							line: newLine,
							column: declaration.location.column,
							endLine: newEndLine,
							endColumn: declaration.location.endColumn
						)
					}
				}

				// Remove from removal state
				removingWarnings.remove(capturedWarningID)

				NotificationCenter.default.post(
					name: Notification.Name("PeripheryWarningRestored"),
					object: capturedWarningID
				)

				// Register redo
				undoManager.registerUndo(withTarget: NSObject()) { _ in
					performRedo()
				}
				undoManager.setActionName("Delete Import")
			}

			// Define the redo action
			@MainActor
			func performRedo() {
				try? capturedModified.write(toFile: capturedPath, atomically: true, encoding: .utf8)
				SourceFileReader.invalidateCache(for: capturedPath)

				// Reapply line number adjustments
				if let sourceGraph = capturedSourceGraph {
					for declaration in sourceGraph.allDeclarations {
						guard declaration.location.file.path.string == capturedPath else { continue }
						guard let declUSR = declaration.usrs.first else { continue }
						guard capturedAdjustedUSRs.contains(declUSR) else { continue }

						let newLine = declaration.location.line - capturedLineAdjustment
						let newEndLine = declaration.location.endLine.map { $0 - capturedLineAdjustment }
						declaration.location = Location(
							file: declaration.location.file,
							line: newLine,
							column: declaration.location.column,
							endLine: newEndLine,
							endColumn: declaration.location.endColumn
						)
					}
				}

				NotificationCenter.default.post(
					name: Notification.Name("PeripheryWarningCompleted"),
					object: capturedWarningID
				)

				// Register undo
				undoManager.registerUndo(withTarget: NSObject()) { _ in
					performUndo()
				}
				undoManager.setActionName("Delete Import")
			}

			// Register initial undo
			undoManager.registerUndo(withTarget: NSObject()) { _ in
				performUndo()
			}
			undoManager.setActionName("Delete Import")
		}

		// Mark action as completed
		completedActions.insert(warningID)

		// Remove from removing state to allow row to hide
		// (row shows while: !isCompleted OR isRemoving, so need to clear both)
		removingWarnings.remove(warningID)

		// Notify that warning was completed
		NotificationCenter.default.post(
			name: Notification.Name("PeripheryWarningCompleted"),
			object: warningID
		)
	}

	/**
	 Inserts a periphery:ignore comment above the declaration.

	 Places the comment before attributes, comments, and the declaration itself,
	 similar to how deletion works. Supports undo/redo.
	 */
	private func insertIgnoreDirective() {
		// Start animation (strikethrough + fade)
		withAnimation(.easeInOut(duration: 0.3)) {
			removingWarnings.insert(warningID)
			ignoringWarnings.insert(warningID)
		}

		// Delay for animation, then insert and remove warning
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(300))

			let filePath = location.file.path.string
			guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

			var lines = originalContents.components(separatedBy: .newlines)
			guard location.line > 0 && location.line <= lines.count else { return }

			// Find the insertion line (same as deletion start line logic)
			let insertionLine = DeclarationDeletionHelper.findDeletionStartLine(
				lines: lines,
				declarationLine: location.line,
				attributes: declaration.attributes
			)

			// Insert the ignore directive
			let insertIndex = insertionLine - 1
			lines.insert("// periphery:ignore", at: insertIndex)

			// Write back to file
			let modifiedContents = lines.joined(separator: "\n")
			try? modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)

			// Invalidate cache
			SourceFileReader.invalidateCache(for: filePath)

			// Adjust line numbers for declarations after this one
			var adjustedUSRs: [String] = []
			if let sourceGraph = sourceGraph {
				for declaration in sourceGraph.allDeclarations {
					guard declaration.location.file.path.string == filePath else { continue }
					guard declaration.location.line >= insertionLine else { continue }

					let newLine = declaration.location.line + 1
					let newEndLine = declaration.location.endLine.map { $0 + 1 }
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
			}

			// Register undo with closure-based redo support
			if let undoManager = undoManager {
				let capturedOriginal = originalContents
				let capturedModified = modifiedContents
				let capturedPath = filePath
				let capturedWarningID = warningID
				let capturedAdjustedUSRs = adjustedUSRs
				let capturedSourceGraph = sourceGraph

				// Define the undo action
				let performUndo: @MainActor () -> Void = {
					try? capturedOriginal.write(toFile: capturedPath, atomically: true, encoding: .utf8)
					SourceFileReader.invalidateCache(for: capturedPath)

					// Reverse line number adjustments
					if let sourceGraph = capturedSourceGraph {
						for declaration in sourceGraph.allDeclarations {
							guard declaration.location.file.path.string == capturedPath else { continue }
							guard let declUSR = declaration.usrs.first else { continue }
							guard capturedAdjustedUSRs.contains(declUSR) else { continue }

							let newLine = declaration.location.line - 1
							let newEndLine = declaration.location.endLine.map { $0 - 1 }
							declaration.location = Location(
								file: declaration.location.file,
								line: newLine,
								column: declaration.location.column,
								endLine: newEndLine,
								endColumn: declaration.location.endColumn
							)
						}
					}

					// Remove from removal/completed state to restore the warning
					removingWarnings.remove(capturedWarningID)
					ignoringWarnings.remove(capturedWarningID)
					completedActions.remove(capturedWarningID)

					NotificationCenter.default.post(
						name: Notification.Name("PeripheryWarningRestored"),
						object: capturedWarningID
					)
				}

				// Define the redo action
				let performRedo: @MainActor () -> Void = {
					try? capturedModified.write(toFile: capturedPath, atomically: true, encoding: .utf8)
					SourceFileReader.invalidateCache(for: capturedPath)

					// Reapply line number adjustments
					if let sourceGraph = capturedSourceGraph {
						for declaration in sourceGraph.allDeclarations {
							guard declaration.location.file.path.string == capturedPath else { continue }
							guard let declUSR = declaration.usrs.first else { continue }
							guard capturedAdjustedUSRs.contains(declUSR) else { continue }

							let newLine = declaration.location.line + 1
							let newEndLine = declaration.location.endLine.map { $0 + 1 }
							declaration.location = Location(
								file: declaration.location.file,
								line: newLine,
								column: declaration.location.column,
								endLine: newEndLine,
								endColumn: declaration.location.endColumn
							)
						}
					}

					// Mark as removed and completed again
					removingWarnings.insert(capturedWarningID)
					ignoringWarnings.insert(capturedWarningID)
					completedActions.insert(capturedWarningID)

					NotificationCenter.default.post(
						name: Notification.Name("PeripheryWarningCompleted"),
						object: capturedWarningID
					)
				}

				// Register initial undo using block-based API
				undoManager.registerUndo(withTarget: undoManager) { undoMgr in
					Task { @MainActor in
						performUndo()
						undoMgr.registerUndo(withTarget: undoMgr) { redoUndoMgr in
							Task { @MainActor in
								performRedo()
								redoUndoMgr.registerUndo(withTarget: redoUndoMgr) { _ in
									Task { @MainActor in
										performUndo()
									}
								}
								redoUndoMgr.setActionName("Insert Ignore Directive")
							}
						}
						undoMgr.setActionName("Insert Ignore Directive")
					}
				}
				undoManager.setActionName("Insert Ignore Directive")
			}

			// Mark action as completed (this will hide the warning from the list)
			completedActions.insert(warningID)
			removingWarnings.remove(warningID)
			ignoringWarnings.remove(warningID)

			// Notify that warning was completed
			NotificationCenter.default.post(
				name: Notification.Name("PeripheryWarningCompleted"),
				object: warningID
			)
		}
	}

	/**
	 Adjusts line numbers for declarations after a file modification.

	 Updates the location of all declarations in the sourceGraph that come after
	 the modified range, accounting for added or removed lines.
	 */
	// Fix redundant public by removing the keyword (internal is default)
	private func fixRedundantPublic() {
		// Verify structural confirmation that 'public' modifier exists
		guard declaration.modifiers.contains("public") else {
			print("Warning: Expected 'public' in modifiers but not found for \(declaration.name ?? "unknown") at \(location.file.path.string):\(location.line)")
			return
		}

		let filePath = location.file.path.string
		guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

		// Register undo
		if let undoManager = undoManager {
			let capturedPath = filePath
			let capturedContents = fileContents
			let capturedWarningID = warningID
			undoManager.registerUndo(withTarget: NSObject()) { _ in
				try? capturedContents.write(toFile: capturedPath, atomically: true, encoding: .utf8)
				SourceFileReader.invalidateCache(for: capturedPath)
				NotificationCenter.default.post(name: Notification.Name("PeripheryWarningRestored"), object: capturedWarningID)
			}
			undoManager.setActionName("Fix Redundant Public")
		}

		// Find and remove 'public' followed by any whitespace on the declaration line
		var lines = fileContents.components(separatedBy: .newlines)
		guard location.line > 0 && location.line <= lines.count else { return }

		let lineIndex = location.line - 1
		let originalLine = lines[lineIndex]

		// Match "public" followed by any whitespace (space, newline, tab, etc.)
		let pattern = #"public\s+"#
		if let regex = try? NSRegularExpression(pattern: pattern) {
			let range = NSRange(originalLine.startIndex..., in: originalLine)
			let newLine = regex.stringByReplacingMatches(
				in: originalLine,
				range: range,
				withTemplate: ""
			)
			lines[lineIndex] = newLine
		}

		let newContents = lines.joined(separator: "\n")
		try? newContents.write(toFile: filePath, atomically: true, encoding: .utf8)

		// Invalidate source file cache so preview shows updated content
		SourceFileReader.invalidateCache(for: filePath)

		// Mark action as completed
		completedActions.insert(warningID)
		removingWarnings.remove(warningID)

		// Notify that warning was completed
		NotificationCenter.default.post(
			name: Notification.Name("PeripheryWarningCompleted"),
			object: warningID
		)
	}

	private func DeleteButton() -> some View {
		Button(
			result.annotation.isUnused ? "Delete declaration" : (isRedundantPublic ? "Remove public keyword" : "Delete"),
			systemImage: "trash",
			action: {
				if result.annotation.isUnused {
					deleteDeclaration()
				} else if isRedundantPublic {
					fixRedundantPublic()
				}
			}
		)
		// Visually hide the text but keep accessibility label
		.labelStyle(.iconOnly)
		.foregroundStyle(.red)
		.frame(width: 16, height: 16)
		.buttonStyle(.plain)
		.help({
			if result.annotation.isUnused {
				canDelete ? "Delete this declaration" : "Can't delete - don't have range"
			} else if isRedundantPublic {
				"Remove public keyword"
			} else {
				""
			}
		}())
		.disabled(result.annotation.isUnused && !canDelete)
		.opacity(completedActions.contains(warningID) || removingWarnings.contains(warningID) ? 0 : 1)
	}

	private func IgnoreButton() -> some View {
		Button("Ignore warning", systemImage: "eye.slash") {
			insertIgnoreDirective()
		}
		.labelStyle(.iconOnly)
		.foregroundStyle(.orange)
		.frame(width: 16, height: 16)
		.buttonStyle(.plain)
		.help("Insert ignore directive")
		.opacity(completedActions.contains(warningID) || removingWarnings.contains(warningID) ? 0 : 1)
	}

	private func ActionButtons() -> some View {
		HStack(spacing: 4) {
			if result.annotation.isUnused || isRedundantPublic {
				DeleteButton()
			}
			IgnoreButton()
		}
	}

	private func source(_ sourceLine: AttributedString) -> some View {
		let isExpanded = expandedWarnings.contains(warningID)
		return HStack(alignment: .top, spacing: 0) {
			// Source line or full preview
			if isExpanded, let fullSource = loadSourcePreview() {
				// Full multi-line source preview
				ScrollView(.horizontal, showsIndicators: true) {
					Text(fullSource)
						.font(.system(.caption, design: .monospaced))
						.textSelection(.enabled)
						.fixedSize(horizontal: true, vertical: false)
						.padding(2)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.secondary.opacity(0.1))
				.clipShape(.rect(cornerRadius:4))
			} else {
				// Single line preview
				Text(sourceLine)
					.textSelection(.enabled)
					.font(.system(.caption, design: .monospaced))
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.tail)
					.padding(2)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background {
						Color(nsColor: .controlBackgroundColor).mix(with: Color.primary, by: 0.05)
							.shadow(color: Color.primary, radius: 1, x: 0, y: 0)
							.mask(Rectangle().padding(.leading, -20))
					}
					.transition(.opacity.combined(with: .move(edge: .top)))
			}
		}
	}

	var body: some View {
		// Cache warningID to avoid multiple accesses to declaration properties
		let warningID = self.warningID
		let isExpanded = expandedWarnings.contains(warningID)
		let isRemoving = removingWarnings.contains(warningID)
		let isIgnoring = ignoringWarnings.contains(warningID)
		let isCompleted = completedActions.contains(warningID)

		// Hide completely if action completed and not removing
		if !isCompleted || isRemoving {
			GridRow {
				// Column 1: Clickable text + badge - opens in Xcode
				Button("Open in Xcode", systemImage: "arrow.forward.circle") {
					openFileInEditor(
						path: location.file.path.string,
						line: location.line
					)
				}
				.labelStyle(.iconOnly)
				.overlay(
					HStack {
						if !isCompleted {
							Text("\(location.line)")
								.font(.body)
								.foregroundStyle(.secondary)
								.monospacedDigit()
								.gridColumnAlignment(.trailing)
						}
						BadgeView(badge: badge)
					}
				)
				.buttonStyle(.plain)
				.help("Open in Xcode at line \(location.line)")
				.gridColumnAlignment(.trailing)
				.strikethrough(isIgnoring)
				.opacity(isRemoving ? 0.5 : 1.0)

				// Column 2: Warning text and source line
				VStack(alignment: .leading, spacing: 0) {
					HStack {
						Text(warningText)
							.font(.body)
							.textSelection(.enabled)
							.frame(maxWidth: .infinity, alignment: .leading)
							.strikethrough(isIgnoring)
						ActionButtons()
					}
				}
				.opacity(isRemoving ? 0.5 : 1.0)
			}
		GridRow {
			// Disclosure button for full source preview (only if multi-line and not completed)
			if !completedActions.contains(warningID) && (result.annotation.isUnused || isRedundantProtocol) && hasFullRange && hasMultiLineSource {
					Button(isExpanded ? "Hide full source" : "Show full source", systemImage: isExpanded ? "chevron.down" : "chevron.right") {
						if isExpanded {
							expandedWarnings.remove(warningID)
						} else {
							expandedWarnings.insert(warningID)
						}
					}
					.labelStyle(.iconOnly)
					.imageScale(.small)
					.foregroundStyle(.secondary)
					.padding(4)
					.contentShape(Rectangle())
					.frame(width: 20, height: 20) // fixed square for the button label area
					.contentShape(Rectangle()) // consistent hit target
					.buttonStyle(.plain)
					.help(isExpanded ? "Hide full source" : "Show full source")
					.gridColumnAlignment(.trailing)
				} else {
					Text("")		// Placeholder for grid
				}
				VStack(alignment: .leading, spacing: 0) {
					if !completedActions.contains(warningID), let sourceLine = sourceLine {
						source(sourceLine)
					}
					// Show assignment locations for assignOnlyProperty warnings
					if case ScanResult.Annotation.assignOnlyProperty = result.annotation, let sourceGraph {
						VStack(alignment: .leading, spacing: 0) {
							// Get the setter accessor to find assignment references
							if let setter = declaration.declarations.first(where: { $0.kind == .functionAccessorSetter }) {
								let assignments = sourceGraph.references(to: setter).sorted()
								ForEach(Array(assignments.enumerated()), id: \.offset) { _, assignment in
									AssignmentLocationRow(assignment: assignment)
								}
							}
						}
					}
					
					// Show usage information for redundant protocol warnings
					if case let ScanResult.Annotation.redundantProtocol(references, inherited) = result.annotation {
						VStack(alignment: .leading, spacing: 0) {
							// Show inherited protocols if any
							if !inherited.isEmpty {
								VStack(alignment: .leading, spacing: 4) {
									Text("Inherits from:")
										.font(.caption)
										.foregroundStyle(.secondary)
									ForEach(Array(inherited.sorted()), id: \.self) { protocolName in
										Text("• \(protocolName)")
											.font(.caption)
											.foregroundStyle(.secondary)
											.padding(.leading, 8)
									}
								}
							}
							
							// Show protocol usage locations
							if !references.isEmpty {
								VStack(alignment: .leading, spacing: 4) {
									Text("Used as constraint in \(references.count) \(references.count == 1 ? "location" : "locations"):")
										.font(.caption)
										.foregroundStyle(.secondary)
									
									let sortedReferences = references.sorted()
									ForEach(Array(sortedReferences.enumerated()), id: \.offset) { _, reference in
										ProtocolReferenceRow(reference: reference)
									}
								}
							}
						}
						.padding(.top, 4)
					}
					
				}
			}
		}
	}
}

private struct AssignmentLocationRow: View {
	let assignment: Reference

	var body: some View {
		DynamicStack(horizontalAlignment: .leading, spacing: 4) {
			// File and line number (clickable)
			Button("Open location", systemImage: "arrow.forward.circle") {
				openFileInEditor(
					path: assignment.location.file.path.string,
					line: assignment.location.line
				)
			}
			.labelStyle(.iconOnly)
			.overlay(
				HStack(spacing: 4) {
					let fileName = assignment.location.file.path.lastComponent ?? "unknown"
					let lineNumber = assignment.location.line
					Text(verbatim: "\(fileName):\(lineNumber)")
						.font(.caption)
						.foregroundStyle(.blue)
				}
			)
			.buttonStyle(.plain)

			// Show containing function/method if available
			if let parent = assignment.parent,
			   let parentName = parent.name {
				Text("in \(parent.kind.displayName) '\(parentName)'")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}
}

/**
 Displays a single protocol reference location for redundant protocol warnings.

 Shows the file and line number where the protocol is used as a constraint,
 with optional parent context (containing type or function).
 */
private struct ProtocolReferenceRow: View {
	let reference: Reference

	var body: some View {
		DynamicStack(horizontalAlignment: .leading, spacing: 4) {
			// File and line number (clickable)
			Button("Open location", systemImage: "arrow.forward.circle") {
				openFileInEditor(
					path: reference.location.file.path.string,
					line: reference.location.line
				)
			}
			.labelStyle(.iconOnly)
			.overlay(
				HStack(spacing: 4) {
					let fileName = reference.location.file.path.lastComponent ?? "unknown"
					let lineNumber = reference.location.line
					Text(verbatim: "\(fileName):\(lineNumber)")
						.font(.caption)
						.foregroundStyle(.blue)
				}
			)
			.buttonStyle(.plain)

			// Show containing type/function if available
			if let parent = reference.parent,
			   let parentName = parent.name {
				Text("in \(parent.kind.displayName) '\(parentName)'")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
		}
	}
}


