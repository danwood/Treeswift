//
//  CodeTreeRowViews.swift
//  Treeswift
//
//  Row views for Categories display (sections, declarations, synthetic roots)
//

import AppKit
import Flow
import SwiftUI

struct SectionRowView: View {
	let section: SectionNode
	@Binding var expandedIDs: Set<String>
	@Binding var selectedID: String?
	var indentLevel: Int
	var projectRootPath: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			DisclosureGroup(
				isExpanded: expansionBinding(for: section.id.rawValue, in: $expandedIDs)
			) {
				ForEach(section.children, id: \.id) { child in
					CategoriesNodeView(
						node: child,
						expandedIDs: $expandedIDs,
						selectedID: $selectedID,
						indentLevel: indentLevel + 1,
						projectRootPath: projectRootPath
					)
					.id(child.id)
				}
			} label: {
				HStack(spacing: 0) {
					ChevronOrPlaceholder(
						hasChildren: !section.children.isEmpty,
						expandedIDs: $expandedIDs,
						id: section.id.rawValue,
						toggleWithDescendants: { toggleWithDescendants(for: .section(section)) }
					)

					Text(section.title)
						.font(.system(.title3, design: .default))
						.fontWeight(.bold)
						.foregroundStyle(.primary)
				}
				.treeLabelPadding(indentLevel: indentLevel)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(selectedID == section.id.rawValue ? Color.accentColor.opacity(0.2) : Color.clear)
				.contentShape(.rect)
				.onTapGesture {
					selectedID = section.id.rawValue
				}
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
			.disclosureGroupStyle(TreeDisclosureStyle())
		}
	}

	private func toggleWithDescendants(for node: CategoriesNode) {
		withAnimation(.easeInOut(duration: 0.2)) {
			expandedIDs.toggleExpansion(
				id: node.id,
				withDescendants: true,
				collectDescendants: { node.collectDescendantIDs() }
			)
		}
	}
}

struct SyntheticRootRowView: View {
	let root: SyntheticRootNode
	@Binding var expandedIDs: Set<String>
	@Binding var selectedID: String?
	var indentLevel: Int
	var projectRootPath: String?

	var body: some View {
		DisclosureGroup(
			isExpanded: expansionBinding(for: root.id, in: $expandedIDs)
		) {
			ForEach(root.children, id: \.id) { child in
				CategoriesNodeView(
					node: child,
					expandedIDs: $expandedIDs,
					selectedID: $selectedID,
					indentLevel: indentLevel + 1,
					projectRootPath: projectRootPath
				)
				.id(child.id)
			}
		} label: {
			HStack(spacing: 0) {
				ChevronOrPlaceholder(
					hasChildren: !root.children.isEmpty,
					expandedIDs: $expandedIDs,
					id: root.id,
					toggleWithDescendants: { toggleWithDescendants(for: .syntheticRoot(root)) }
				)

				HStack(spacing: 4) {
					root.icon.view(size: 14)
					Text(root.title)
						.font(.system(.body, design: .monospaced))
				}
			}
			.treeLabelPadding(indentLevel: indentLevel)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(selectedID == root.id ? Color.accentColor.opacity(0.2) : Color.clear)
			.contentShape(.rect)
			.onTapGesture {
				selectedID = root.id
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
		.disclosureGroupStyle(TreeDisclosureStyle())
	}

	private func toggleWithDescendants(for node: CategoriesNode) {
		withAnimation(.easeInOut(duration: 0.2)) {
			expandedIDs.toggleExpansion(
				id: node.id,
				withDescendants: true,
				collectDescendants: { node.collectDescendantIDs() }
			)
		}
	}
}

struct DeclarationRowView: View {
	let declaration: DeclarationNode
	@Binding var expandedIDs: Set<String>
	@Binding var selectedID: String?
	var indentLevel: Int
	var projectRootPath: String?
	@Environment(\.showCodeSize) private var showCodeSize
	@Environment(\.showFileInfo) private var showFileInfo
	@Environment(\.showFileName) private var showFileName
	@Environment(\.showConformance) private var showConformance
	@Environment(\.showPath) private var showPath

	/**
	 Checks if the filename matches the symbol name
	 */
	private var fileNameMatchesSymbol: Bool {
		guard let fileName = declaration.locationInfo.fileName else { return false }
		let fileNameWithoutExtension = (fileName as NSString).deletingPathExtension
		return fileNameWithoutExtension == declaration.displayName
	}

	/**
	 Returns location info display text without the filename and icon portions
	 */

	var body: some View {
		let cachedFileNameMatchesSymbol = fileNameMatchesSymbol

		return VStack(alignment: .leading, spacing: 0) {
			DisclosureGroup(
				isExpanded: expansionBinding(for: declaration.id, in: $expandedIDs)
			) {
				ForEach(declaration.children, id: \.id) { child in
					CategoriesNodeView(
						node: child,
						expandedIDs: $expandedIDs,
						selectedID: $selectedID,
						indentLevel: indentLevel + 1,
						projectRootPath: projectRootPath
					)
					.id(child.id)
				}
			} label: {
				HStack(alignment: .firstTextBaseline, spacing: 4) {
					ChevronOrPlaceholder(
						hasChildren: !declaration.children.isEmpty,
						expandedIDs: $expandedIDs,
						id: declaration.id,
						toggleWithDescendants: { toggleWithDescendants(for: .declaration(declaration)) }
					)

					if let folderIndicator = declaration.folderIndicator {
						folderIndicator.view(size: 14)
					}
					declaration.typeIcon.view(size: 14)
					if showFileName, cachedFileNameMatchesSymbol {
						Text(declaration.displayName)
							.font(.body)
							+ Text(".swift")
							.font(.system(.body, design: .monospaced))
							.foregroundStyle(.secondary)

					} else {
						Text(declaration.displayName)
					}

					if showConformance, let conformances = declaration.conformances {
						Text(": \(conformances)")
					}

					// not quite what I want, leave out for now
					// if showFileInfo {
					// 	if declaration.isSameFileAsChildren == true {
					// 		TreeIcon.systemImage("document.fill", Color.purple).view(size: 14)
					// 	}
					// }

					// if let relationship = declaration.relationship, relationship != RelationshipType.constructs {
					// 	Text("{\(relationship.rawValue)}")
					// 		.font(.system(.body, design: .monospaced))
					// 		.foregroundStyle(.secondary)
					// }

					if showFileName,
					   !cachedFileNameMatchesSymbol, !declaration.locationInfo.displayText.isEmpty,
					   !(declaration.locationInfo.type == .swiftNested || declaration.locationInfo.type == .sameFile) {
						Text(declaration.locationInfo.displayText)
							.font(.system(.body, design: .monospaced))
							.foregroundStyle(.secondary)
							.foregroundStyle(.purple)
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
							.font(.caption2)
					}

					if showCodeSize {
						if !showPath {
							Spacer() // Only spacer if we didn't already use it for path
						}

						LineSizeGraph(
							line: declaration.locationInfo.line,
							endLine: declaration.locationInfo.endLine
						)
						.frame(width: 100)
						.help("\((declaration.locationInfo.endLine ?? 0) - declaration.locationInfo.line) lines")
					}
				}
				.treeLabelPadding(indentLevel: indentLevel)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(selectedID == declaration.id ? Color.accentColor.opacity(0.2) : Color.clear)
				.contentShape(.rect)
				.onTapGesture {
					selectedID = declaration.id
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
			}
			.disclosureGroupStyle(TreeDisclosureStyle())
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

			if let referencerInfo = declaration.referencerInfo {
				VStack(alignment: .leading, spacing: 2) {
					ForEach(Array(referencerInfo.enumerated()), id: \.offset) { index, info in
						Text(index == 0 ? "     ← \(info)" : "       \(info)")
							.font(.system(.caption, design: .monospaced))
							.foregroundStyle(.secondary)
							.treeLabelPadding(indentLevel: indentLevel)
					}
				}
			}
		}
	}

	private func toggleWithDescendants(for node: CategoriesNode) {
		withAnimation(.easeInOut(duration: 0.2)) {
			expandedIDs.toggleExpansion(
				id: node.id,
				withDescendants: true,
				collectDescendants: { node.collectDescendantIDs() }
			)
		}
	}
}
