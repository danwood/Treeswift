//
//  TreeCopyFormatter.swift
//  Treeswift
//
//  Copy formatting utilities for tree nodes
//

import AppKit
import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

enum TreeCopyFormatter {
	// Generate periphery-format output for TreeNode
	static func formatForCopy(
		node: TreeNode,
		scanResults: [ScanResult],
		filterState: FilterState? = nil
	) -> String {
		switch node {
		case let .file(file):
			var lines: [String] = []
			collectWarnings(from: .file(file), scanResults: scanResults, filterState: filterState, into: &lines)
			return lines.joined(separator: "\n")

		case let .folder(folder):
			var lines: [String] = []
			collectWarnings(from: .folder(folder), scanResults: scanResults, filterState: filterState, into: &lines)
			return lines.joined(separator: "\n")
		}
	}

	// Generate indented output for FileBrowserNode
	// Generate indented output for CategoriesNode
	static func formatForCopy(
		node: CategoriesNode,
		includeDescendants: Bool = true,
		indentLevel: Int = 0
	) -> String {
		var lines: [String] = []
		let indent = String(repeating: "\t", count: indentLevel)

		switch node {
		case let .section(section):
			lines.append(indent + section.title)
			if includeDescendants {
				for child in section.children {
					lines.append(formatForCopy(
						node: child,
						includeDescendants: true,
						indentLevel: indentLevel + 1
					))
				}
			}

		case let .declaration(decl):
			var text = ""
			if let folderIndicator = decl.folderIndicator {
				text += folderIndicator.asText + " "
			}
			text += decl.typeIcon.asText + " "
			text += decl.displayName
			if !decl.conformances.isEmpty {
				text += decl.conformances
			}
			if let relationship = decl.relationship {
				text += " {\(relationship)}"
			}
			text += " " + decl.locationInfo.displayText
			lines.append(indent + text)

			if includeDescendants {
				for child in decl.children {
					lines.append(formatForCopy(
						node: child,
						includeDescendants: true,
						indentLevel: indentLevel + 1
					))
				}
			}

		case let .syntheticRoot(root):
			lines.append(indent + root.icon.asText + " " + root.title)
			if includeDescendants {
				for child in root.children {
					lines.append(formatForCopy(
						node: child,
						includeDescendants: true,
						indentLevel: indentLevel + 1
					))
				}
			}
		}

		return lines.joined(separator: "\n")
	}

	/**
	 Recursively collect all warnings from a tree node
	 */
	private static func collectWarnings(
		from node: TreeNode,
		scanResults: [ScanResult],
		filterState: FilterState?,
		into lines: inout [String]
	) {
		switch node {
		case let .file(file):
			// Filter warnings for this specific file
			let fileWarnings = scanResults
				.compactMap { scanResult -> (scanResult: ScanResult, declaration: Declaration, location: Location)? in
					let declaration = scanResult.declaration
					let location = ScanResultHelper.location(from: declaration)

					// Match file path
					guard location.file.path.string == file.path else { return nil }

					// Apply filter state if present
					if let filterState {
						guard filterState.shouldShow(scanResult: scanResult, declaration: declaration)
						else { return nil }
					}

					return (scanResult, declaration, location)
				}
				.sorted { lhs, rhs in
					// Sort by line number, then column number
					if lhs.location.line != rhs.location.line {
						return lhs.location.line < rhs.location.line
					}
					return lhs.location.column < rhs.location.column
				}

			// Format each warning in Xcode format
			for (scanResult, declaration, location) in fileWarnings {
				let warningLine = ScanResultHelper.formatPlainTextWarning(
					declaration: declaration,
					scanResult: scanResult,
					location: location
				)
				lines.append(warningLine)
			}

		case let .folder(folder):
			// Recursively collect warnings from all children
			for child in folder.children {
				collectWarnings(from: child, scanResults: scanResults, filterState: filterState, into: &lines)
			}
		}
	}

	// Copy text to clipboard
	static func copyToClipboard(_ text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}
}
