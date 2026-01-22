//
//  CategoriesDetailView.swift
//  Treeswift
//
//  Detail view for selected items in Categories tab
//

import AppKit
import SwiftUI

struct CategoriesDetailView: View {
	let node: CategoriesNode

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			switch node {
			case let .section(section):
				sectionDetailView(section)
			case let .declaration(declaration):
				declarationDetailView(declaration)
			case let .syntheticRoot(root):
				rootDetailView(root)
			}
		}
	}

	private func sectionDetailView(_ section: SectionNode) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "folder")
					.foregroundStyle(.blue)
				Text(section.title)
					.font(.title2)
					.fontWeight(.semibold)
			}

			Text("\(section.children.count) items")
				.font(.body)
				.foregroundStyle(.secondary)
		}
	}

	private func declarationDetailView(_ declaration: DeclarationNode) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			// Header with icon
			HStack(spacing: 4) {
				if let folderIndicator = declaration.folderIndicator {
					folderIndicator.view(size: 20)
				}
				declaration.typeIcon.view(size: 20)
				Text(declaration.displayName)
					.font(.system(.title2, design: .default))
					.fontWeight(.semibold)
			}

			// Icon explanation
			VStack(alignment: .leading, spacing: 2) {
				if declaration.folderIndicator != nil {
					Text("In its own folder (good organization)")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				if let typeExplanation = typeIconExplanation(declaration.typeIcon) {
					Text(typeExplanation)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Divider()
			}

			// Conformances
			if !declaration.conformances.isEmpty {
				VStack(alignment: .leading, spacing: 4) {
					Text("Conformances")
						.font(.headline)
					Text(declaration.conformances)
						.font(.body)
						.foregroundStyle(.secondary)
						.textSelection(.enabled)
				}
			}

			// Relationship
			if let relationship = declaration.relationship {
				VStack(alignment: .leading, spacing: 4) {
					Text("Relationship")
						.font(.headline)
					Text(relationship.rawValue)
						.font(.body)
						.foregroundStyle(.secondary)
						.textSelection(.enabled)
					Divider()
				}
			}

			// Location info
			VStack(alignment: .leading, spacing: 8) {
				Text("Location")
					.font(.headline)

				HStack(spacing: 4) {
					if let icon = declaration.locationInfo.icon {
						icon.view(size: 14)
					}
					let displayFileName = declaration.locationInfo
						.fileName ?? extractFileName(from: declaration.locationInfo.relativePath)
					if let fileName = displayFileName {
						Text(fileName)
							.font(.system(.caption, design: .monospaced))
							.foregroundStyle(.secondary)
						Text(":\(declaration.locationInfo.line)")
							.font(.system(.caption, design: .monospaced))
							.foregroundStyle(.secondary)

						Button(action: {
							openDeclarationInEditor(declaration)
						}) {
							Image(systemName: "arrow.right.circle.fill")
								.foregroundStyle(.secondary)
						}
						.buttonStyle(.plain)
						.help("Open in Xcode")
					}
				}
				.textSelection(.enabled)

				// Location icon explanation
				if let icon = declaration.locationInfo.icon, let locationExplanation = locationIconExplanation(icon) {
					Text(locationExplanation)
						.font(.caption)
						.foregroundStyle(.secondary)
				}

				if let warningText = declaration.locationInfo.warningText {
					Text(warningText)
						.font(.caption)
						.foregroundStyle(.orange)
				}
			}

			// Referencers
			if let referencers = declaration.referencerInfo, !referencers.isEmpty {
				Divider()
				VStack(alignment: .leading, spacing: 8) {
					Text("Referenced By")
						.font(.headline)

					ForEach(referencers.prefix(10), id: \.self) { referencer in
						HStack(spacing: 6) {
							Text("•")
								.foregroundStyle(.secondary)
							Text(referencer)
								.font(.caption)
								.foregroundStyle(.secondary)
								.textSelection(.enabled)
						}
					}

					if referencers.count > 10 {
						Text("... and \(referencers.count - 10) more")
							.font(.caption)
							.foregroundStyle(.tertiary)
					}
				}
			}
		}
	}

	// FIXME: redundant with DetailTopLevelSymbolsSection.iconTooltip(for:…)
	private func typeIconExplanation(_ icon: TreeIcon) -> String? {
		guard case let .emoji(emoji) = icon else { return nil }
		switch emoji {
		case "🔷": return "Main App entry point (@main)"
		case "🖼️": return "SwiftUI View"
		case "🟤": return "AppKit class (inherits from NS* type)"
		case "🟦": return "Struct"
		case "🔵": return "Class"
		case "🚦": return "Enum"
		case "📜": return "Protocol"
		case "⚡️": return "Function"
		case "🫥": return "Property or Variable"
		case "⬜️": return "Other declaration type"
		default: return nil
		}
	}

	private func locationIconExplanation(_ icon: TreeIcon) -> String? {
		guard case let .emoji(emoji) = icon else { return nil }
		switch emoji {
		case "🆘": return "Declaration is too large for its current file"
		case "📎": return "Swift-nested type (defined inside another type)"
		case "🔼": return "In same file as parent type"
		case "😒": return "Too small to warrant a separate file"
		case "🛑": return "File name doesn't match declaration name"
		default: return nil
		}
	}

	private func extractFileName(from relativePath: String?) -> String? {
		guard let path = relativePath else { return nil }
		return (path as NSString).lastPathComponent
	}

	private func openDeclarationInEditor(_ declaration: DeclarationNode) {
		guard declaration.locationInfo.fileName != nil else { return }
		/* The DeclarationNode only stores the file name, not the full path.
		 Opening by file name alone would require searching for the file.
		 For now, just open Xcode and let the user navigate. */
		NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app"))
	}

	private func rootDetailView(_ root: SyntheticRootNode) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(root.title)
				.font(.title2)
				.fontWeight(.semibold)

			Text("\(root.children.count) top-level items")
				.font(.body)
				.foregroundStyle(.secondary)
		}
	}
}
