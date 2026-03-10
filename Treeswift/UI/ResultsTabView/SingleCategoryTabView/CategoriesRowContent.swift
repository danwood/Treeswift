//
//  CategoriesRowContent.swift
//  Treeswift
//
//  Flat row content for OutlineGroup — renders just the label for a CategoriesNode
//

import AppKit
import SwiftUI

// Row content for a CategoriesNode inside an OutlineGroup.
// Renders only the label; OutlineGroup handles disclosure/indentation.
/* folderprivate */ struct CategoriesRowContent: View {
	let node: CategoriesNode
	var projectRootPath: String?

	var body: some View {
		switch node {
		case let .section(section):
			SectionLabel(section: section)

		case let .declaration(decl):
			DeclarationLabel(declaration: decl, projectRootPath: projectRootPath)

		case let .syntheticRoot(root):
			SyntheticRootLabel(root: root)
		}
	}
}

// Section label (title only)
private struct SectionLabel: View {
	let section: SectionNode

	var body: some View {
		Text(section.title)
			.font(.system(.title3, design: .default))
			.bold()
			.foregroundStyle(.primary)
			.contextMenu {
				Button("Copy") {
					let text = TreeCopyFormatter.formatForCopy(
						node: .section(section),
						includeDescendants: true,
						indentLevel: 0
					)
					TreeCopyFormatter.copyToClipboard(text)
				}
				.keyboardShortcut("c", modifiers: .command)
			}
	}
}

// Synthetic root label (icon + title)
private struct SyntheticRootLabel: View {
	let root: SyntheticRootNode

	var body: some View {
		HStack(spacing: 4) {
			root.icon.view(size: 14)
			Text(root.title)
				.font(.system(.body, design: .monospaced))
		}
		.contextMenu {
			Button("Copy") {
				let text = TreeCopyFormatter.formatForCopy(
					node: .syntheticRoot(root),
					includeDescendants: true,
					indentLevel: 0
				)
				TreeCopyFormatter.copyToClipboard(text)
			}
			.keyboardShortcut("c", modifiers: .command)
		}
	}
}

// Declaration label (icons + name + optional metadata)
private struct DeclarationLabel: View {
	let declaration: DeclarationNode
	var projectRootPath: String?
	@Environment(\.showCodeSize) private var showCodeSize
	@Environment(\.showFileInfo) private var showFileInfo
	@Environment(\.showFileName) private var showFileName
	@Environment(\.showConformance) private var showConformance
	@Environment(\.showPath) private var showPath

	private var fileNameMatchesSymbol: Bool {
		guard let fileName = declaration.locationInfo.fileName else { return false }
		let fileNameWithoutExtension = (fileName as NSString).deletingPathExtension
		return fileNameWithoutExtension == declaration.displayName
	}

	var body: some View {
		let cachedFileNameMatchesSymbol = fileNameMatchesSymbol

		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .firstTextBaseline, spacing: 4) {
				if let folderIndicator = declaration.folderIndicator {
					folderIndicator.view(size: 14)
				}
				declaration.typeIcon.view(size: 14)
				if showFileName, cachedFileNameMatchesSymbol {
					let name = Text(declaration.displayName).font(.body)
					let suffix = Text(".swift")
						.font(.system(.body, design: .monospaced))
						.foregroundStyle(.secondary)
					Text("\(name)\(suffix)")
				} else {
					Text(declaration.displayName)
				}

				if showConformance, let conformances = declaration.conformances {
					Text(": \(conformances)")
				}

				if showFileName,
				   !cachedFileNameMatchesSymbol, !declaration.locationInfo.displayText.isEmpty,
				   !(declaration.locationInfo.type == .swiftNested || declaration.locationInfo
				   	.type == .sameFile) {
					Text(declaration.locationInfo.displayText)
						.font(.system(.body, design: .monospaced))
						.foregroundStyle(.secondary)
				}
				if showFileInfo {
					if let icon = declaration.locationInfo.icon {
						icon.view(size: 14)
							.help(declaration.locationInfo.fileName ?? "")
					}
				}

				if showPath {
					Spacer()
					Text(declaration.containerPath)
						.font(.caption)
				}

				if showCodeSize {
					if !showPath {
						Spacer()
					}

					LineSizeGraph(
						line: declaration.locationInfo.line,
						endLine: declaration.locationInfo.endLine
					)
					.frame(width: 100)
					.help("\((declaration.locationInfo.endLine ?? 0) - declaration.locationInfo.line) lines")
				}
			}

			if let referencerInfo = declaration.referencerInfo {
				VStack(alignment: .leading, spacing: 2) {
					ForEach(referencerInfo.indices, id: \.self) { index in
						Text(index == 0 ? "     ← \(referencerInfo[index])" : "       \(referencerInfo[index])")
							.font(.system(.caption, design: .monospaced))
							.foregroundStyle(.secondary)
					}
				}
			}
		}
		.simultaneousGesture(
			TapGesture(count: 2)
				.onEnded {
					if let relativePath = declaration.locationInfo.relativePath,
					   let projectRoot = projectRootPath {
						let fullPath = (projectRoot as NSString).appendingPathComponent(relativePath)
						openFileInEditor(path: fullPath, line: declaration.locationInfo.line)
					}
				}
		)
		.contextMenu {
			Button("Copy") {
				let text = TreeCopyFormatter.formatForCopy(
					node: .declaration(declaration),
					includeDescendants: true,
					indentLevel: 0
				)
				TreeCopyFormatter.copyToClipboard(text)
			}
			.keyboardShortcut("c", modifiers: .command)

			if let relativePath = declaration.locationInfo.relativePath,
			   let projectRoot = projectRootPath {
				let fullPath = (projectRoot as NSString).appendingPathComponent(relativePath)
				let fileURL = URL(fileURLWithPath: fullPath)
				Button("Reveal in Finder") {
					NSWorkspace.shared.activateFileViewerSelecting([fileURL])
				}
			}

			Divider()

			OrganizeViewIntoFolderAction(
				declaration: declaration,
				projectRootPath: projectRootPath
			)
		}
	}
}
