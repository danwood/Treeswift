//
//  DetailTopLevelSymbolsSection.swift
//  Treeswift
//
//  Detail section showing all top-level symbols defined in a file
//

import SwiftUI

struct DetailTopLevelSymbolsSection: View {
	let symbols: [FileTypeInfo]
	let filePath: String

	private var sortedSymbols: [FileTypeInfo] {
		symbols.sorted { lhs, rhs in
			if lhs.matchesFileName != rhs.matchesFileName {
				return lhs.matchesFileName
			}
			return false
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Public/Static Symbols")
				.font(.headline)

			// Compute values directly from symbols
			let symbolCount = symbols.count
			let singleSymbolMatchesFileName = (symbolCount == 1) && (symbols.first?.matchesFileName == true)

			HStack(spacing: 6) {
				Image(systemName: singleSymbolMatchesFileName ? "checkmark.circle.fill" : "info.circle")
					.foregroundStyle(singleSymbolMatchesFileName ? .green : .secondary)
					.font(.caption)
				Text(symbolCount == 1 ? "1 symbol" : "\(symbolCount) symbols")
					.font(.caption)
					.foregroundStyle(.secondary)
				if singleSymbolMatchesFileName {
					Text("• matches filename")
						.font(.caption)
						.foregroundStyle(.green)
				}
			}

			VStack(alignment: .leading, spacing: 8) {
				ForEach(sortedSymbols, id: \.name) { symbolInfo in
					VStack(alignment: .leading, spacing: 2) {
						HStack(spacing: 6) {
							Text(symbolInfo.icon)
								.font(.system(.body))
								.help(iconTooltip(for: symbolInfo.icon))
								.onTapGesture(count: 2) {
									openFileInEditor(path: filePath, line: symbolInfo.startLine)
								}
								.contentShape(.rect)

							Text(symbolInfo.name)
								.font(.system(.body, design: .monospaced))
								.foregroundStyle(symbolInfo.isUnused ? .orange : .primary)
								.textSelection(.enabled)

							if symbolInfo.matchesFileName {
								Text("(primary)")
									.font(.caption)
									.foregroundStyle(.green)
							}

							if symbolInfo.isUnused {
								Text("(unused)")
									.font(.caption)
									.foregroundStyle(.orange)
							}

							if symbolInfo.isRedundantPublic {
								Text("(redundant public)")
									.font(.caption)
									.foregroundStyle(.secondary)
							}
						}

						// Reference information
						if !symbolInfo.referencingFileNames.isEmpty {
							Text("← \(symbolInfo.referencingFileNames.joined(separator: ", "))")
								.font(.caption)
								.foregroundStyle(.secondary)
								.padding(.leading, 24)
						}
					}
				}
			}
		}
		.padding(.vertical, 4)
	}

	private func iconTooltip(for icon: String) -> String {
		switch icon {
		case "🔷": "Main App entry point (@main)"
		case "🖼️": "SwiftUI View"
		case "🟤": "AppKit class (inherits from NS* type)"
		case "🟦": "Struct"
		case "🔵": "Class"
		case "🚦": "Enum"
		case "📜": "Protocol"
		case "⚡️": "Function"
		case "🫥": "Property or Variable"
		case "🏷️": "Type alias"
		case "🔮": "Macro"
		case "⚖️": "Precedence group"
		case "🧩": "Extension"
		case "⬜️": "Other declaration type"
		default: "Symbol"
		}
	}
}
