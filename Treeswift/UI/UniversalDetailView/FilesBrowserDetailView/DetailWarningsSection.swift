//
//  DetailWarningsSection.swift
//  Treeswift
//
//  Detail section showing analysis warnings for a file or folder
//

import SwiftUI

struct DetailWarningsSection: View {
	let warnings: [AnalysisWarning]

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Analysis Warnings")
				.font(.headline)

			ForEach(Array(warnings.enumerated()), id: \.offset) { index, warning in
				VStack(alignment: .leading, spacing: 8) {
					// Severity icon + message
					HStack(alignment: .top, spacing: 6) {
						Text(severityIcon(for: warning.severity))
							.font(.body)
						Text(warning.message)
							.font(.body)
							.foregroundStyle(foregroundStyle(for: warning))
							.textSelection(.enabled)
					}

					// Details
					if let details = warning.details, !details.isEmpty {
						VStack(alignment: .leading, spacing: 4) {
							ForEach(details, id: \.self) { detail in
								Text(detail)
									.font(.caption)
									.foregroundStyle(.secondary)
									.textSelection(.enabled)
							}
						}
						.padding(.leading, 28) // Align with message text
					}

					// Suggested actions
					if !warning.suggestedActions.isEmpty {
						VStack(alignment: .leading, spacing: 4) {
							Text("Suggested actions:")
								.font(.caption)
								.foregroundStyle(.secondary)
								.padding(.top, 4)

							let sortedActions = warning.suggestedActions.keys.sorted { $0.displayText < $1.displayText }
							ForEach(sortedActions, id: \.self) { action in
								let isCompleted = warning.suggestedActions[action] ?? false
								let prefix = isCompleted ? "✓" : "•"
								HStack(spacing: 6) {
									Text(prefix)
										.foregroundStyle(.secondary)
									Text(action.displayText)
										.font(.caption)
										.foregroundStyle(.secondary)
										.textSelection(.enabled)
								}
							}
						}
						.padding(.leading, 28) // Align with message text
					}

					// Symbol references
					if let symbolRefs = warning.symbolReferences, !symbolRefs.isEmpty {
						VStack(alignment: .leading, spacing: 8) {
							// Main symbols section
							let mainSymbols = symbolRefs.filter(\.shouldBePublic)
							if !mainSymbols.isEmpty {
								Text("✓ Should be public/internal:")
									.font(.caption)
									.foregroundStyle(.green)
									.padding(.top, 4)

								ForEach(mainSymbols, id: \.symbolName) { symbolRef in
									HStack(spacing: 6) {
										Text(symbolRef.icon)
											.font(.system(.caption))
											.onTapGesture(count: 2) {
												openFileInEditor(path: symbolRef.filePath, line: symbolRef.line)
											}
											.contentShape(.rect)

										Text(symbolRef.symbolName)
											.font(.caption)
											.foregroundStyle(.green)
											.textSelection(.enabled)
											.onTapGesture(count: 2) {
												openFileInEditor(path: symbolRef.filePath, line: symbolRef.line)
											}
											.contentShape(.rect)

										Text("(double-click to open)")
											.font(.caption2)
											.foregroundStyle(.tertiary)
									}
									.padding(.leading, 12)
								}
							}

							// Leaked symbols section
							let leakedSymbols = symbolRefs.filter { !$0.shouldBePublic }
							if !leakedSymbols.isEmpty {
								Text("✗ Should be private/fileprivate:")
									.font(.caption)
									.foregroundStyle(.red)
									.padding(.top, 4)

								ForEach(leakedSymbols, id: \.symbolName) { symbolRef in
									HStack(spacing: 6) {
										Text(symbolRef.icon)
											.font(.system(.caption))
											.onTapGesture(count: 2) {
												openFileInEditor(path: symbolRef.filePath, line: symbolRef.line)
											}
											.contentShape(.rect)

										Text(symbolRef.symbolName)
											.font(.caption)
											.foregroundStyle(.red)
											.textSelection(.enabled)
											.onTapGesture(count: 2) {
												openFileInEditor(path: symbolRef.filePath, line: symbolRef.line)
											}
											.contentShape(.rect)

										Text("(double-click to open)")
											.font(.caption2)
											.foregroundStyle(.tertiary)
									}
									.padding(.leading, 12)
								}
							}
						}
						.padding(.leading, 28) // Align with message text
					}

					if index < warnings.count - 1 {
						Divider()
							.padding(.top, 4)
					}
				}
			}
		}
		.padding(.vertical, 4)
	}

	private func severityIcon(for severity: WarningSeverity) -> String {
		switch severity {
		case .info: "💡"
		case .warning: "⚠️"
		case .error: "❌"
		}
	}

	private func foregroundStyle(for warning: AnalysisWarning) -> Color {
		// Check if warning has "Move to" action - use purple for consistency with file browser
		let hasMoveToAction = warning.suggestedActions.keys.contains { action in
			if case .moveFileToFolder = action {
				return true
			}
			return false
		}

		if hasMoveToAction {
			return .purple
		}

		// Use standard colors based on severity
		switch warning.severity {
		case .info: return .blue
		case .warning: return .orange
		case .error: return .red
		}
	}
}
