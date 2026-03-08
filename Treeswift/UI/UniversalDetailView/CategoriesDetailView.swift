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
				SectionDetailContent(section: section)
			case let .declaration(declaration):
				DeclarationDetailContent(declaration: declaration)
			case let .syntheticRoot(root):
				RootDetailContent(root: root)
			}
		}
	}
}

private struct SectionDetailContent: View {
	let section: SectionNode

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			HStack {
				Image(systemName: "folder")
					.foregroundStyle(.blue)
				Text(section.title)
					.font(.title2)
					.bold()
			}

			Text("\(section.children.count) items")
				.font(.body)
				.foregroundStyle(.secondary)
		}
	}
}

private struct DeclarationDetailContent: View {
	let declaration: DeclarationNode

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			// Header with icon
			HStack(spacing: 4) {
				if let folderIndicator = declaration.folderIndicator {
					folderIndicator.view(size: 20)
				}
				declaration.typeIcon.view(size: 20)
				Text(declaration.displayName)
					.font(.system(.title2, design: .default))
					.bold()
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
			if let conformances = declaration.conformances {
				VStack(alignment: .leading, spacing: 4) {
					Text("Conformances")
						.font(.headline)
					Text(conformances)
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

						Button("Open in Xcode", systemImage: "arrow.right.circle.fill") {
							openDeclarationInEditor(declaration)
						}
						.labelStyle(.iconOnly)
						.foregroundStyle(.secondary)
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
	func typeIconExplanation(_ icon: TreeIcon) -> String? {
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

	func locationIconExplanation(_ icon: TreeIcon) -> String? {
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

	func extractFileName(from relativePath: String?) -> String? {
		guard let path = relativePath else { return nil }
		return (path as NSString).lastPathComponent
	}

	func openDeclarationInEditor(_ declaration: DeclarationNode) {
		guard declaration.locationInfo.fileName != nil else { return }
		// The DeclarationNode only stores the file name, not the full path.
		// Opening by file name alone would require searching for the file.
		// For now, just open Xcode and let the user navigate.
		if let xcodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") {
			NSWorkspace.shared.open(xcodeURL)
		}
	}
}

private struct RootDetailContent: View {
	let root: SyntheticRootNode

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(root.title)
				.font(.title2)
				.bold()

			Text("\(root.children.count) top-level items")
				.font(.body)
				.foregroundStyle(.secondary)
		}
	}
}
