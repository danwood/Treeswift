//
//  ScanCache.swift
//  Treeswift
//
//  On-disk representation of completed scan results.
//  Stored at: ~/Library/Application Support/Treeswift/ScanCache/scan-cache-<UUID>.json
//

import Foundation

nonisolated struct ScanCache: Codable, Sendable {
	static let currentSchemaVersion = 2

	let configurationID: UUID
	let schemaVersion: Int
	let cachedAt: Date
	let projectPath: String?
	let treeNodes: [TreeNodeResponse]
	let treeSection: CategoriesNodeResponse?
	let viewExtensionsSection: CategoriesNodeResponse?
	let sharedSection: CategoriesNodeResponse?
	let orphansSection: CategoriesNodeResponse?
	let previewOrphansSection: CategoriesNodeResponse?
	let bodyGetterSection: CategoriesNodeResponse?
	let unattachedSection: CategoriesNodeResponse?
	let fileTreeNodes: [FileBrowserNodeResponse]
	// Source graph and scan results for full removal functionality after restore
	let declarationSnapshots: [DeclarationSnapshot]
	let referenceSnapshots: [ReferenceSnapshot]
	let scanResultSnapshots: [ScanResultSnapshot]

	// MARK: - Response → Live Model Conversions

	nonisolated func restoreTreeNodes() -> [TreeNode] {
		treeNodes.map { Self.toTreeNode($0) }
	}

	nonisolated func restoreCategoriesNode(_ response: CategoriesNodeResponse) -> CategoriesNode {
		Self.toCategoriesNode(response)
	}

	nonisolated func restoreFileTreeNodes() -> [FileBrowserNode] {
		fileTreeNodes.map { Self.toFileBrowserNode($0) }
	}

	// MARK: - Private Converters

	private nonisolated static func toTreeNode(_ response: TreeNodeResponse) -> TreeNode {
		if response.type == "folder" {
			let children = (response.children ?? []).map { toTreeNode($0) }
			return .folder(FolderNode(id: response.id, name: response.name, path: response.path, children: children))
		} else {
			return .file(FileNode(id: response.id, name: response.name, path: response.path))
		}
	}

	private nonisolated static func toCategoriesNode(_ response: CategoriesNodeResponse) -> CategoriesNode {
		switch response.type {
		case "section":
			let sectionID = CategorySection(rawValue: response.id) ?? .hierarchy
			let children = response.children.map { toCategoriesNode($0) }
			return .section(SectionNode(id: sectionID, title: response.title ?? "", children: children))
		case "syntheticRoot":
			let icon: TreeIcon = response.typeIconSystemName.map { .systemImage($0) } ?? .systemImage("folder")
			let children = response.children.map { toCategoriesNode($0) }
			return .syntheticRoot(SyntheticRootNode(
				id: response.id,
				title: response.title ?? "",
				icon: icon,
				children: children
			))
		default: // "declaration"
			let typeIcon: TreeIcon = response.typeIconSystemName.map { .systemImage($0) }
				?? (response.typeIconEmoji.map { .emoji($0) } ?? .systemImage("doc"))
			let locationInfo = LocationInfo(
				type: .sameFile,
				icon: nil,
				fileName: response.filePath.map { URL(fileURLWithPath: $0).lastPathComponent },
				relativePath: response.filePath,
				line: response.line ?? 0,
				endLine: nil,
				warningText: nil
			)
			let relationship = response.relationship.flatMap { RelationshipType(rawValue: $0) }
			let children = response.children.map { toCategoriesNode($0) }
			return .declaration(DeclarationNode(
				id: response.id,
				folderIndicator: nil,
				typeIcon: typeIcon,
				isView: response.isView ?? false,
				isSameFileAsChildren: nil,
				displayName: response.displayName ?? "",
				containerPath: response.containerPath ?? "",
				conformances: response.conformances,
				relationship: relationship,
				locationInfo: locationInfo,
				referencerInfo: nil,
				children: children
			))
		}
	}

	private nonisolated static func toFileBrowserNode(_ response: FileBrowserNodeResponse) -> FileBrowserNode {
		if response.type == "directory" {
			let children = (response.children ?? []).map { toFileBrowserNode($0) }
			return .directory(FileBrowserDirectory(
				id: response.id,
				name: response.name,
				children: children,
				containsSwiftFiles: response.containsSwiftFiles ?? true
			))
		} else {
			let usageBadge = response.usageBadge.map { parseUsageBadge($0) }
			return .file(FileBrowserFile(
				id: response.id,
				name: response.name,
				path: response.path ?? "",
				usageBadge: usageBadge
			))
		}
	}

	/**
	 Parses a usage badge string of the form "text (warning|positive|neutral)" back into a UsageBadge.
	 */
	private nonisolated static func parseUsageBadge(_ string: String) -> UsageBadge {
		if let parenRange = string.range(of: " (", options: .backwards),
		   let closeRange = string.range(of: ")", options: .backwards),
		   parenRange.upperBound < closeRange.lowerBound {
			let text = String(string[string.startIndex ..< parenRange.lowerBound])
			let qualifier = String(string[parenRange.upperBound ..< closeRange.lowerBound])
			return UsageBadge(text: text, isWarning: qualifier == "warning", isPositive: qualifier == "positive")
		}
		return UsageBadge(text: string, isWarning: false, isPositive: false)
	}
}
