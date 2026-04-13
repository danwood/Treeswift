//
//  DetailPeripheryWarningsSection.swift
//  Treeswift
//
//  Detail section showing Periphery scan warnings for a file
//

import PeripheryKit
import SourceGraph
import SwiftUI
import SystemPackage

private struct OperationError: Identifiable {
	let id = UUID()
	let message: String
}

struct DetailPeripheryWarningsSection: View {
	private let filePath: String
	private let scanResults: [ScanResult]
	private let sourceGraph: (any SourceGraphProtocol)?
	private let filterState: FilterState?

	@AppStorage("showPeripheryWarningDetails") private var showDetails: Bool = false
	@State private var expandedWarnings: Set<String> = []
	@State private var completedActions: Set<String> = []
	@State private var refreshTrigger: Int = 0
	@State private var removingWarnings: Set<String> = []
	@State private var ignoringWarnings: Set<String> = []
	@State private var operationError: OperationError?

	// Initialize with optional filter state
	init(
		filePath: String,
		scanResults: [ScanResult],
		sourceGraph: (any SourceGraphProtocol)? = nil,
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
			.compactMap { scanResult -> (result: ScanResult, declaration: Declaration)? in
				let declaration = scanResult.declaration
				let location = ScanResultHelper.location(from: declaration)

				// Match file path
				guard location.file.path.string == filePath else { return nil }

				// Apply filter state if provided
				if let filterState {
					guard filterState.shouldShow(scanResult: scanResult, declaration: declaration) else {
						return nil
					}
				}

				return (scanResult, declaration)
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
		Group {
			if !fileWarnings.isEmpty {
				VStack(alignment: .leading, spacing: 12) {
					DynamicStack(spacing: 8) {
						Text("Periphery Warnings")
							.font(.headline)
						Spacer()
						Toggle("Show Details", isOn: $showDetails)
							.toggleStyle(.switch)
							.controlSize(.small)
					}

					Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 4) {
						ForEach(fileWarnings, id: \.declaration.usrs.first) { tuple in
							PeripheryWarningRow(
								scanResult: tuple.result,
								declaration: tuple.declaration,
								showDetails: showDetails,
								sourceGraph: sourceGraph,
								expandedWarnings: $expandedWarnings,
								completedActions: $completedActions,
								refreshTrigger: $refreshTrigger,
								removingWarnings: $removingWarnings,
								ignoringWarnings: $ignoringWarnings,
								operationError: $operationError
							)
						}
					}
					.id(refreshTrigger)
					.animation(.easeInOut(duration: 0.2), value: showDetails)
				}
				.padding(.vertical, 4)
				.task {
					for await notification in NotificationCenter.default.notifications(
						named: Notification.Name("PeripheryWarningRestored")
					) {
						if let warningID = notification.object as? String {
							completedActions.remove(warningID)
							refreshTrigger += 1
						}
					}
				}
				.task {
					for await notification in NotificationCenter.default.notifications(
						named: Notification.Name("PeripheryWarningCompleted")
					) {
						if let warningID = notification.object as? String {
							completedActions.insert(warningID)
							refreshTrigger += 1
						}
					}
				}
			}
		}
		// Binding(get:set:) is intentional — macOS SwiftUI does not expose the
		// .alert(item:) overload that iOS has, so isPresented with a manual binding
		// is the only way to drive an alert from an optional model value on macOS.
		.alert(
			"Operation Failed",
			isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })
		) {
			Text(operationError?.message ?? "")
		}
	}
}

// Individual warning row with clickable badge and selectable text - shared component
private struct PeripheryWarningRow: View {
	let scanResult: ScanResult
	let declaration: Declaration
	let showDetails: Bool
	let sourceGraph: (any SourceGraphProtocol)?
	@Binding var expandedWarnings: Set<String>
	@Binding var completedActions: Set<String>
	@Binding var refreshTrigger: Int
	@Binding var removingWarnings: Set<String>
	@Binding var ignoringWarnings: Set<String>
	@Binding var operationError: OperationError?
	@Environment(\.undoManager) var undoManager

	@State var cachedSourceLine: AttributedString?
	@State var cachedHasMultiLineSource: Bool = false
	@State var cachedCanFindSuperfluousIgnore: Bool = false

	// Read location from declaration so it updates when declaration.location changes
	var location: Location {
		ScanResultHelper.location(from: declaration)
	}

	var badge: Badge {
		let swiftType = SwiftType.from(declarationKind: declaration.kind)
		return Badge(
			letter: swiftType.rawValue,
			count: 1,
			swiftType: swiftType,
			isUnused: scanResult.annotation == .unused
		)
	}

	var warningText: AttributedString {
		ScanResultHelper.formatAttributedDescription(
			declaration: declaration,
			scanResult: scanResult
		)
	}

	// Generate unique ID for this warning using stable USR
	var warningID: String {
		let usr = declaration.usrs.first ?? ""
		return "\(location.file.path.string):\(usr)"
	}

	// Check if location has full range info for deletion
	var hasFullRange: Bool {
		location.endLine != nil && location.endColumn != nil
	}

	// Check if this is an import declaration
	var isImport: Bool {
		declaration.kind == .module
	}

	// Check if declaration can be deleted (has full range or is import)
	var canDelete: Bool {
		hasFullRange || isImport
	}

	func computeSourceLine() -> AttributedString? {
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
				// First, check if the declaration line itself has a @ modifier
				let declarationLineIndex = location.line - 1
				if declarationLineIndex >= 0, declarationLineIndex < lines.count {
					let declarationFullLine = lines[declarationLineIndex]

					// If declaration line has @ modifier, format with secondary styling
					if let atIndex = declarationFullLine.firstIndex(of: "@") {
						// Find where the @ modifier ends (at whitespace after closing paren or after modifier name)
						var modifierEndIndex = atIndex

						// Find end of modifier (skip past @Name or @Name(...))
						var idx = declarationFullLine.index(after: atIndex)
						var foundParen = false
						while idx < declarationFullLine.endIndex {
							let char = declarationFullLine[idx]
							if char == "(" {
								foundParen = true
							} else if foundParen, char == ")" {
								// Move past closing paren, but don't skip whitespace
								idx = declarationFullLine.index(after: idx)
								modifierEndIndex = idx
								break
							} else if !foundParen, char.isWhitespace {
								// Found end of simple @Modifier (don't include the whitespace)
								modifierEndIndex = idx
								break
							}
							idx = declarationFullLine.index(after: idx)
						}

						// Split line into modifier and declaration parts
						let modifierPart = String(declarationFullLine[atIndex ..< modifierEndIndex])
						let declarationPart = String(declarationFullLine[modifierEndIndex...])

						// Build attributed string with secondary styling for modifier
						var result = AttributedString()

						// Modifier part - secondary color, regular weight
						var modifierAttr = AttributedString(modifierPart)
						modifierAttr.font = .system(.caption, design: .monospaced)
						modifierAttr.foregroundColor = Color.secondary
						result.append(modifierAttr)

						// Declaration part - highlight symbol with semibold (don't trim, preserve spacing)
						if let symbolName = declaration.name, !symbolName.isEmpty,
						   let symbolRange = declarationPart.range(of: symbolName) {
							let beforeSymbol = String(declarationPart[..<symbolRange.lowerBound])
							let symbol = String(declarationPart[symbolRange])
							let afterSymbol = String(declarationPart[symbolRange.upperBound...])

							let highlightColor = Color(nsColor: .selectedTextBackgroundColor).opacity(0.4)

							var beforeAttr = AttributedString(beforeSymbol)
							beforeAttr.font = .system(.caption, design: .monospaced).weight(.semibold)
							result.append(beforeAttr)

							var symbolAttr = AttributedString(symbol)
							symbolAttr.backgroundColor = highlightColor
							symbolAttr.font = .system(.caption, design: .monospaced).weight(.semibold)
							result.append(symbolAttr)

							var afterAttr = AttributedString(afterSymbol)
							afterAttr.font = .system(.caption, design: .monospaced).weight(.semibold)
							result.append(afterAttr)
						} else {
							// No symbol highlighting, just make declaration part semibold
							var declAttr = AttributedString(declarationPart)
							declAttr.font = .system(.caption, design: .monospaced).weight(.semibold)
							result.append(declAttr)
						}

						return result
					}
				}

				// If no @ modifier on declaration line, look in lines before
				for lineNum in startLine ..< location.line {
					let lineIndex = lineNum - 1
					guard lineIndex >= 0, lineIndex < lines.count else { continue }
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
								symbolName: declaration.name,
								makeDeclarationBold: true
							)
						}
					}
				}
			}
		}

		// For redundant public warnings, highlight the "public " keyword instead of the symbol
		if case .redundantPublicAccessibility = scanResult.annotation {
			return ScanResultHelper.highlightRedundantPublicInLine(line: lineText)
		}

		// For superfluous ignore commands, show entire line in secondary color (no highlighting)
		// since we're removing the comment, not the declaration
		if scanResult.annotation == .superfluousIgnoreCommand {
			var result = AttributedString(lineText)
			result.font = .system(.caption, design: .monospaced)
			result.foregroundColor = Color.secondary
			return result
		}

		return ScanResultHelper.highlightSymbolInSourceLine(
			line: lineText,
			column: location.column,
			symbolName: declaration.name
		)
	}

	func computeHasMultiLineSource() -> Bool {
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

		return startLine < location.line
	}

	// Load source code preview for a declaration
	func loadSourcePreview() -> String? {
		guard let endLine = location.endLine else { return nil }

		let filePath = location.file.path.string
		guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }

		let lines = fileContents.components(separatedBy: .newlines)
		guard location.line > 0, location.line <= lines.count else { return nil }
		guard endLine > 0, endLine <= lines.count else { return nil }

		// Find actual start line including attributes and comments
		let startLine = DeclarationDeletionHelper.findDeletionStartLine(
			lines: lines,
			declarationLine: location.line,
			attributes: declaration.attributes
		)

		let startIndex = startLine - 1
		let endIndex = endLine - 1
		let relevantLines = lines[startIndex ... endIndex]

		return relevantLines.joined(separator: "\n")
	}

	// Delete declaration from source file
	func deleteDeclaration() {
		// Start fade-out animation
		withAnimation(.easeInOut(duration: 0.3)) {
			removingWarnings.insert(warningID)
		}

		// Delay for animation, then delete
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(300))

			let result: Result<Void, Error>

				// Special case for imports (single line deletion)
				= if isImport {
				CodeModificationHelper.executeImportDeletion(
					location: location,
					sourceGraph: sourceGraph,
					undoManager: undoManager,
					warningID: warningID,
					onComplete: { [self] in
						WarningStateManager.completeWarning(
							warningID: warningID,
							completedActions: &completedActions,
							removingWarnings: &removingWarnings
						)
					},
					onRestore: { [self] in
						WarningStateManager.restoreWarning(
							warningID: warningID,
							completedActions: &completedActions,
							removingWarnings: &removingWarnings
						)
					}
				)
			}
			// Use enhanced deletion with sourceGraph if available
			else if let sourceGraph, hasFullRange {
				CodeModificationHelper.executeDeclarationDeletion(
					declaration: declaration,
					location: location,
					sourceGraph: sourceGraph,
					undoManager: undoManager,
					warningID: warningID,
					onComplete: { [self] in
						WarningStateManager.completeWarning(
							warningID: warningID,
							completedActions: &completedActions,
							removingWarnings: &removingWarnings
						)
					},
					onRestore: { [self] in
						WarningStateManager.restoreWarning(
							warningID: warningID,
							completedActions: &completedActions,
							removingWarnings: &removingWarnings
						)
					}
				)
			} else {
				// Fallback to simple deletion when sourceGraph is missing
				CodeModificationHelper.executeSimpleDeclarationDeletion(
					declaration: declaration,
					location: location,
					sourceGraph: sourceGraph,
					undoManager: undoManager,
					warningID: warningID,
					onComplete: { [self] in
						WarningStateManager.completeWarning(
							warningID: warningID,
							completedActions: &completedActions,
							removingWarnings: &removingWarnings
						)
					},
					onRestore: { [self] in
						WarningStateManager.restoreWarning(
							warningID: warningID,
							completedActions: &completedActions,
							removingWarnings: &removingWarnings
						)
					}
				)
			}

			// Handle errors
			if case let .failure(error) = result {
				operationError = OperationError(message: "Failed to delete declaration: \(error.localizedDescription)")
				removingWarnings.remove(warningID)
			}
		}
	}

	/**
	 Inserts a periphery:ignore comment above the declaration.

	 Places the comment before attributes, comments, and the declaration itself,
	 similar to how deletion works. Supports undo/redo.
	 */
	func insertIgnoreDirective() {
		// Start animation (strikethrough + fade)
		withAnimation(.easeInOut(duration: 0.3)) {
			removingWarnings.insert(warningID)
			ignoringWarnings.insert(warningID)
		}

		// Delay for animation, then insert and remove warning
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(300))

			let result = CodeModificationHelper.executeIgnoreCommentInsertion(
				declaration: declaration,
				location: location,
				sourceGraph: sourceGraph,
				undoManager: undoManager,
				warningID: warningID,
				onComplete: { [self] in
					// Mark action as completed
					WarningStateManager.completeWarning(
						warningID: warningID,
						completedActions: &completedActions,
						removingWarnings: &removingWarnings
					)
					ignoringWarnings.remove(warningID)
				},
				onRestore: { [self] in
					// Restore the warning
					WarningStateManager.restoreWarning(
						warningID: warningID,
						completedActions: &completedActions,
						removingWarnings: &removingWarnings
					)
					ignoringWarnings.remove(warningID)
				}
			)

			// Handle errors
			if case let .failure(error) = result {
				operationError =
					OperationError(message: "Failed to insert ignore directive: \(error.localizedDescription)")
				removingWarnings.remove(warningID)
				ignoringWarnings.remove(warningID)
			}
		}
	}

	/**
	 Removes superfluous periphery:ignore comment.

	 Scans backwards from declaration to find and remove the ignore directive.
	 Handles all Periphery ignore formats and removes trailing blank lines.
	 */
	func fixSuperfluousIgnoreCommand() {
		let result = CodeModificationHelper.removeSuperfluousIgnoreComment(
			declaration: declaration,
			location: location
		)

		switch result {
		case let .success(modification):
			// Invalidate cache
			SourceFileReader.invalidateCache(for: modification.filePath)

			// Adjust line numbers if lines were removed
			let adjustedUSRs = sourceGraph.map { modification.adjustSourceGraph($0) } ?? []

			if !adjustedUSRs.isEmpty {
				// Register undo with source graph reversal
				registerModificationUndoWithLineAdjustment(
					modification: modification,
					adjustedUSRs: adjustedUSRs,
					actionName: "Delete Ignore Comment"
				)
			} else {
				registerModificationUndo(modification: modification, actionName: "Delete Ignore Comment")
			}

			// Mark completed and notify
			completeWarning()

		case let .failure(error):
			operationError = OperationError(message: "Failed to remove ignore command: \(error.localizedDescription)")
		}
	}

	// Fix redundant access control by removing or inserting keywords
	func fixAccessControl() {
		let fix: AccessControlFix

		switch scanResult.annotation {
		case .redundantPublicAccessibility:
			fix = .removePublic
		case let .redundantInternalAccessibility(suggestedAccessibility):
			// Trust Periphery metadata to determine which keyword to insert
			if let suggested = suggestedAccessibility {
				switch suggested {
				case .private: fix = .insertPrivate
				case .fileprivate: fix = .insertFilePrivate
				default: return
				}
			} else {
				fix = .removeInternal
			}
		case .redundantFilePrivateAccessibility:
			fix = .insertPrivate
		case .redundantAccessibility:
			// Remove whatever access keyword is present
			fix = .removeAccessibility(current: String?(nil))
		default:
			return
		}

		let result = CodeModificationHelper.fixAccessControl(
			declaration: declaration,
			location: location,
			fix: fix
		)

		switch result {
		case let .success(modification):
			// Invalidate cache
			SourceFileReader.invalidateCache(for: modification.filePath)

			// Register undo
			registerModificationUndo(modification: modification, actionName: "Fix Access Control")

			// Mark completed and notify
			completeWarning()

		case let .failure(error):
			operationError = OperationError(message: "Failed to fix access control: \(error.localizedDescription)")
		}
	}

	/**
	 Registers undo for a simple modification (no line number adjustments).
	 */
	func registerModificationUndo(
		modification: CodeModificationHelper.ModificationResult,
		actionName: String
	) {
		UndoRedoHelper.registerModificationUndo(
			undoManager: undoManager,
			modification: modification,
			warningID: warningID,
			actionName: actionName,
			onComplete: { [self] in
				WarningStateManager.completeWarning(
					warningID: warningID,
					completedActions: &completedActions,
					removingWarnings: &removingWarnings
				)
			},
			onRestore: { [self] in
				WarningStateManager.restoreWarning(
					warningID: warningID,
					completedActions: &completedActions,
					removingWarnings: &removingWarnings
				)
			}
		)
	}

	/**
	 Registers undo for a modification that includes line number adjustments.
	 */
	func registerModificationUndoWithLineAdjustment(
		modification: CodeModificationHelper.ModificationResult,
		adjustedUSRs: [String],
		actionName: String
	) {
		UndoRedoHelper.registerModificationUndoWithLineAdjustment(
			undoManager: undoManager,
			modification: modification,
			warningID: warningID,
			adjustedUSRs: adjustedUSRs,
			sourceGraph: sourceGraph,
			actionName: actionName,
			onComplete: { [self] in
				WarningStateManager.completeWarning(
					warningID: warningID,
					completedActions: &completedActions,
					removingWarnings: &removingWarnings
				)
			},
			onRestore: { [self] in
				WarningStateManager.restoreWarning(
					warningID: warningID,
					completedActions: &completedActions,
					removingWarnings: &removingWarnings
				)
			}
		)
	}

	/**
	 Marks a warning as completed and posts notification.
	 */
	func completeWarning() {
		WarningStateManager.completeWarning(
			warningID: warningID,
			completedActions: &completedActions,
			removingWarnings: &removingWarnings
		)
	}

	/**
	 Determines if the superfluous ignore comment can be deleted.

	 Returns true if the ignore comment can be found, false otherwise.
	 For non-superfluous-ignore warnings, always returns true.
	 */
	var canDeleteSuperfluousIgnore: Bool {
		if scanResult.annotation != .superfluousIgnoreCommand {
			return true
		}
		return cachedCanFindSuperfluousIgnore
	}

	func computeCanFindSuperfluousIgnoreComment() -> Bool {
		let filePath = location.file.path.string
		guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return false
		}
		let lines = fileContents.components(separatedBy: .newlines)
		return CommentScanner.findCommentContaining(
			pattern: "periphery:ignore",
			in: lines,
			backwardFrom: location.line,
			maxDistance: 10
		) != nil
	}

	var body: some View {
		// Cache warningID to avoid multiple accesses to declaration properties
		let warningID = warningID
		let isExpanded = expandedWarnings.contains(warningID)
		let isRemoving = removingWarnings.contains(warningID)
		let isIgnoring = ignoringWarnings.contains(warningID)
		let isCompleted = completedActions.contains(warningID)
		let sourceLine = cachedSourceLine
		let hasMultiLineSource = cachedHasMultiLineSource

		// Hide completely if action completed and not removing
		Group {
			if !isCompleted || isRemoving {
				GridRow {
					// Column 1: Line number + badge - opens in Xcode
					Button {
						openFileInEditor(
							path: location.file.path.string,
							line: location.line
						)
					} label: {
						HStack(spacing: 4) {
							if !isCompleted {
								Text("\(location.line)")
									.font(.body)
									.foregroundStyle(.secondary)
									.monospacedDigit()
							}
							BadgeView(badge: badge)
						}
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Open in Xcode at line \(location.line)")
					.strikethrough(isIgnoring)
					.opacity(isRemoving ? 0.5 : 1.0)
					.help("Open in Xcode at line \(location.line)")
					.gridColumnAlignment(.trailing)

					// Column 2: Warning text and source line
					VStack(alignment: .leading, spacing: 0) {
						HStack {
							Text(warningText)
								.font(.body)
								.textSelection(.enabled)
								.frame(maxWidth: .infinity, alignment: .leading)
								.strikethrough(isIgnoring)
							WarningActionButtons(
								annotation: scanResult.annotation,
								hasFullRange: hasFullRange,
								isImport: isImport,
								warningID: warningID,
								canDelete: canDelete,
								canDeleteSuperfluousIgnore: canDeleteSuperfluousIgnore,
								completedActions: completedActions,
								removingWarnings: removingWarnings,
								onDelete: deleteDeclaration,
								onFixAccessControl: fixAccessControl,
								onFixSuperfluousIgnore: fixSuperfluousIgnoreCommand,
								onIgnore: insertIgnoreDirective
							)
						}
					}
					.opacity(isRemoving ? 0.5 : 1.0)
				}
				GridRow {
					let isRedundantProtocol = if case .redundantProtocol = scanResult.annotation { true } else { false }

					// FIXME: Use ChevronExpansionButton
					// Disclosure button for full source preview (only if multi-line and not completed)
					if !completedActions.contains(warningID),
					   scanResult.annotation == .unused || isRedundantProtocol, hasFullRange,
					   hasMultiLineSource {
						Button(
							isExpanded ? "Hide full source" : "Show full source",
							systemImage: isExpanded ? "chevron.down" : "chevron.right"
						) {
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
						Text("") // Placeholder for grid
					}
					VStack(alignment: .leading, spacing: 0) {
						if !completedActions.contains(warningID), let sourceLine {
							WarningSourceView(
								sourceLine: sourceLine,
								isExpanded: expandedWarnings.contains(warningID),
								fullSource: loadSourcePreview()
							)
						}
						// Show assignment locations for assignOnlyProperty warnings
						if case ScanResult.Annotation.assignOnlyProperty = scanResult.annotation, let sourceGraph {
							VStack(alignment: .leading, spacing: 0) {
								// Get the setter accessor to find assignment references
								if let setter = declaration.declarations
									.first(where: { $0.kind == .functionAccessorSetter }) {
									let assignments = sourceGraph.references(to: setter).sorted()
									ForEach(assignments.enumerated(), id: \.offset) { _, assignment in
										AssignmentLocationRow(assignment: assignment)
									}
								}
							}
						}

						// Show usage information for redundant protocol warnings
						if case let ScanResult.Annotation.redundantProtocol(references, inherited) = scanResult
							.annotation {
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
										Text(
											"Used as constraint in \(references.count) \(references.count == 1 ? "location" : "locations"):"
										)
										.font(.caption)
										.foregroundStyle(.secondary)

										let sortedReferences = references.sorted()
										ForEach(sortedReferences.enumerated(), id: \.offset) { _, reference in
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
		.task(id: showDetails) {
			cachedSourceLine = computeSourceLine()
		}
		.task {
			cachedHasMultiLineSource = computeHasMultiLineSource()
			cachedCanFindSuperfluousIgnore = computeCanFindSuperfluousIgnoreComment()
		}
	}
}

private struct WarningDeleteButton: View {
	let annotation: ScanResult.Annotation
	let warningID: String
	let canDelete: Bool
	let canDeleteSuperfluousIgnore: Bool
	let completedActions: Set<String>
	let removingWarnings: Set<String>
	let onDelete: () -> Void
	let onFixAccessControl: () -> Void
	let onFixSuperfluousIgnore: () -> Void

	var label: String {
		switch annotation {
		case .unused: "Delete declaration"
		case .redundantPublicAccessibility: "Remove public keyword"
		case let .redundantInternalAccessibility(suggestedAccessibility):
			"Make \(suggestedAccessibility?.rawValue, default: "fileprivate/private")"
		case .redundantFilePrivateAccessibility: "Make private"
		case .redundantAccessibility: "Remove accessibility modifier"
		case .superfluousIgnoreCommand: "Delete Periphery Ignore command"
		default: ""
		}
	}

	var icon: String {
		switch annotation {
		case .unused: "trash"
		case .redundantPublicAccessibility: "eye.slash"
		case .redundantInternalAccessibility: "eye.slash"
		case .redundantFilePrivateAccessibility: "eye.slash"
		case .redundantAccessibility: "trash"
		case .superfluousIgnoreCommand: "trash"
		default: "trash"
		}
	}

	var color: Color {
		switch annotation {
		case .unused: .red
		case .redundantPublicAccessibility: .blue
		case .redundantInternalAccessibility: .blue
		case .redundantFilePrivateAccessibility: .blue
		case .redundantAccessibility: .red
		case .superfluousIgnoreCommand: .red
		default: .red
		}
	}

	var helpText: String {
		if annotation == .unused {
			canDelete ? "Delete this declaration" : "Can't delete - don't have range"
		} else if case .redundantPublicAccessibility = annotation {
			"Remove public keyword"
		} else if case let .redundantInternalAccessibility(suggestedAccessibility) = annotation {
			"Replace access with \(suggestedAccessibility, default: "fileprivate/private")"
		} else if case .redundantFilePrivateAccessibility = annotation {
			"Replace access with private"
		} else if case .redundantAccessibility = annotation {
			"Remove access keyword"
		} else if annotation == .superfluousIgnoreCommand {
			canDeleteSuperfluousIgnore
				? "Remove Superfluous ignore command"
				: "Can't find comment - must be deleted manually"
		} else {
			""
		}
	}

	var isDisabled: Bool {
		(annotation == .unused && !canDelete) ||
			(annotation == .superfluousIgnoreCommand && !canDeleteSuperfluousIgnore)
	}

	var body: some View {
		Button(label, systemImage: icon) {
			if annotation == .unused {
				onDelete()
			} else if case .redundantPublicAccessibility = annotation {
				onFixAccessControl()
			} else if case .redundantInternalAccessibility = annotation {
				onFixAccessControl()
			} else if case .redundantFilePrivateAccessibility = annotation {
				onFixAccessControl()
			} else if case .redundantAccessibility = annotation {
				onFixAccessControl()
			} else if annotation == .superfluousIgnoreCommand {
				onFixSuperfluousIgnore()
			}
		}
		// Visually hide the text but keep accessibility label
		.labelStyle(.iconOnly)
		.foregroundStyle(color)
		.frame(width: 16, height: 16)
		.buttonStyle(.plain)
		.help(helpText)
		.disabled(isDisabled)
		.opacity(completedActions.contains(warningID) || removingWarnings.contains(warningID) ? 0 : 1)
	}
}

private struct WarningIgnoreButton: View {
	let warningID: String
	let completedActions: Set<String>
	let removingWarnings: Set<String>
	let onIgnore: () -> Void

	var body: some View {
		Button("Ignore warning", systemImage: "bell.slash", action: onIgnore)
			.labelStyle(.iconOnly)
			.foregroundStyle(.orange)
			.frame(width: 16, height: 16)
			.buttonStyle(.plain)
			.help("Insert ignore directive")
			.opacity(completedActions.contains(warningID) || removingWarnings.contains(warningID) ? 0 : 1)
	}
}

private struct WarningActionButtons: View {
	let annotation: ScanResult.Annotation
	let hasFullRange: Bool
	let isImport: Bool
	let warningID: String
	let canDelete: Bool
	let canDeleteSuperfluousIgnore: Bool
	let completedActions: Set<String>
	let removingWarnings: Set<String>
	let onDelete: () -> Void
	let onFixAccessControl: () -> Void
	let onFixSuperfluousIgnore: () -> Void
	let onIgnore: () -> Void

	var body: some View {
		HStack(spacing: 4) {
			if annotation.canRemoveCode(hasFullRange: hasFullRange, isImport: isImport) {
				WarningDeleteButton(
					annotation: annotation,
					warningID: warningID,
					canDelete: canDelete,
					canDeleteSuperfluousIgnore: canDeleteSuperfluousIgnore,
					completedActions: completedActions,
					removingWarnings: removingWarnings,
					onDelete: onDelete,
					onFixAccessControl: onFixAccessControl,
					onFixSuperfluousIgnore: onFixSuperfluousIgnore
				)
			}
			// Can't ignore a superfluous ignore!
			if annotation != .superfluousIgnoreCommand {
				WarningIgnoreButton(
					warningID: warningID,
					completedActions: completedActions,
					removingWarnings: removingWarnings,
					onIgnore: onIgnore
				)
			}
		}
	}
}

private struct WarningSourceView: View {
	let sourceLine: AttributedString
	let isExpanded: Bool
	let fullSource: String?

	var body: some View {
		HStack(alignment: .top, spacing: 0) {
			if isExpanded, let fullSource {
				// Full multi-line source preview
				ScrollView(.horizontal) {
					Text(fullSource)
						.font(.system(.caption, design: .monospaced))
						.textSelection(.enabled)
						.fixedSize(horizontal: true, vertical: false)
						.padding(2)
				}
				.scrollIndicators(.visible)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.secondary.opacity(0.1))
				.clipShape(.rect(cornerRadius: 4))
			} else {
				// Single line preview
				Text(sourceLine)
					.textSelection(.enabled)
					.font(.system(.caption, design: .monospaced))
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
}

private struct AssignmentLocationRow: View {
	let assignment: Reference

	var body: some View {
		DynamicStack(horizontalAlignment: .leading, spacing: 4) {
			// File and line number (clickable)
			Button {
				openFileInEditor(
					path: assignment.location.file.path.string,
					line: assignment.location.line
				)
			} label: {
				HStack(spacing: 4) {
					Image(systemName: "arrow.forward.circle")
						.foregroundStyle(.secondary)
						.font(.caption)
					let fileName = assignment.location.file.path.lastComponent ?? "unknown"
					let lineNumber = assignment.location.line
					Text(verbatim: "\(fileName):\(lineNumber)")
						.font(.caption)
						.foregroundStyle(.blue)
				}
			}
			.buttonStyle(.plain)
			.help("Open in Xcode")

			// Show containing function/method if available
			if let parent = assignment.parent,
			   let parentName = parent.name {
				// Truncate long initializer signatures
				let displayName = truncateInitializer(parentName, maxLength: 60)
				Text("in \(parent.kind.displayName) '\(displayName)'")
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
		}
	}

	/**
	 Truncates long initializer signatures for display.

	 For initializers with long parameter lists, shows just "init(...)" instead of the full signature.
	 */
	func truncateInitializer(_ name: String, maxLength: Int) -> String {
		guard name.count > maxLength else { return name }

		// For initializers, just show "init(...)"
		if name.hasPrefix("init(") {
			return "init(...)"
		}

		// For other long names, truncate with ellipsis
		let truncated = name.prefix(maxLength)
		return "\(truncated)..."
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
			Button {
				openFileInEditor(
					path: reference.location.file.path.string,
					line: reference.location.line
				)
			} label: {
				HStack(spacing: 4) {
					Image(systemName: "arrow.forward.circle")
						.foregroundStyle(.secondary)
						.font(.caption)
					let fileName = reference.location.file.path.lastComponent ?? "unknown"
					let lineNumber = reference.location.line
					Text(verbatim: "\(fileName):\(lineNumber)")
						.font(.caption)
						.foregroundStyle(.blue)
				}
			}
			.buttonStyle(.plain)
			.help("Open in Xcode")

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
