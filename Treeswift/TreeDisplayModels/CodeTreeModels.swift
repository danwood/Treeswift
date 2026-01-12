//
//  CategoriesModels.swift
//  Treeswift
//
//  Data models for Categories visualization (from Dumper analysis)
//

import Foundation

/**
Type-safe enum for identifying category sections
*/
enum CategorySection: String, CaseIterable, Sendable {
	case hierarchy = "section-hierarchy"
	case viewExtensions = "section-view-extensions"
	case shared = "section-shared-types"
	case orphaned = "section-orphaned"
	case previewOrphaned = "section-preview-orphaned"
	case bodyGetter = "section-body-getter"
	case unattached = "section-unattached"
}

enum CategoriesNode: Identifiable, Hashable, Sendable {
	case section(SectionNode)
	case declaration(DeclarationNode)
	case syntheticRoot(SyntheticRootNode)

	var id: String {
		switch self {
		case .section(let node): node.id.rawValue
		case .declaration(let node): node.id
		case .syntheticRoot(let node): node.id
		}
	}

	// Collects all descendant IDs recursively
	func collectDescendantIDs() -> Set<String> {
		var result = Set<String>()
		collectDescendantIDs(into: &result)
		return result
	}

	private func collectDescendantIDs(into set: inout Set<String>) {
		switch self {
		case .section(let section):
			set.insert(section.id.rawValue)
			for child in section.children {
				child.collectDescendantIDs(into: &set)
			}
		case .declaration(let decl):
			set.insert(decl.id)
			for child in decl.children {
				child.collectDescendantIDs(into: &set)
			}
		case .syntheticRoot(let root):
			set.insert(root.id)
			for child in root.children {
				child.collectDescendantIDs(into: &set)
			}
		}
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}

	static func == (lhs: CategoriesNode, rhs: CategoriesNode) -> Bool {
		lhs.id == rhs.id
	}
}

struct SectionNode: Identifiable, Hashable, Sendable {
	let id: CategorySection
	let title: String
	var children: [CategoriesNode]

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}

	static func == (lhs: SectionNode, rhs: SectionNode) -> Bool {
		lhs.id == rhs.id
	}
}

enum RelationshipType: String {
	case embed = "EMBED"
	case subview = "SUBVIEW"
	case prop = "PROP"
	case param = "PARAM"
	case local = "LOCAL"
	case staticMember = "STATIC"
	case call = "CALL"
	case constructs = "CONSTRUCTS"
	case type = "TYPE"
	case inherit = "INHERIT"
	case conform = "CONFORM"
	case generic = "GENERIC"
	case ref = "REF"
}

struct DeclarationNode: Identifiable, Hashable, Sendable {
	let id: String
	let folderIndicator: TreeIcon?
	let typeIcon: TreeIcon
	let isView: Bool
	let displayName: String
	let conformances: String
	let relationship: RelationshipType?
	let locationInfo: LocationInfo
	let referencerInfo: [String]?
	var children: [CategoriesNode]

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}

	static func == (lhs: DeclarationNode, rhs: DeclarationNode) -> Bool {
		lhs.id == rhs.id
	}
}

struct SyntheticRootNode: Identifiable, Hashable, Sendable {
	let id: String
	let title: String
	let icon: TreeIcon
	var children: [CategoriesNode]

	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}

	static func == (lhs: SyntheticRootNode, rhs: SyntheticRootNode) -> Bool {
		lhs.id == rhs.id
	}
}

extension CategoriesNode: NavigableTreeNode {
	var navigationID: String { id }

	var isExpandable: Bool {
		switch self {
		case .section(let section): !section.children.isEmpty
		case .declaration(let decl): !decl.children.isEmpty
		case .syntheticRoot(let root): !root.children.isEmpty
		}
	}

	var childNodes: [any NavigableTreeNode] {
		switch self {
		case .section(let section): section.children
		case .declaration(let decl): decl.children
		case .syntheticRoot(let root): root.children
		}
	}
}

struct LocationInfo: Hashable, Sendable {
	enum LocationType: Hashable, Sendable {
		case swiftNested
		case sameFile
		case separateFileGood
		case separateFileTooSmall
		case separateFileNameMismatch
		case tooBigForSameFile
	}

	// periphery:ignore - kept for future use even though currently unused
	let type: LocationType
	let icon: TreeIcon
	let fileName: String?
	let relativePath: String?
	let line: Int
	let endLine: Int?
	let sizeIndicator: String
	let warningText: String?

	var displayText: String {
		var parts: [String] = []

		if let fileName = fileName {
			let lineRange = if let endLine = endLine {
				"\(line):\(endLine)"
			} else {
				"\(line)"
			}
			parts.append("\(fileName):\(lineRange)")
		}

		parts.append(icon.asText)

		if let warningText = warningText {
			parts.append(warningText)
		}

		if !sizeIndicator.isEmpty {
			parts.append(sizeIndicator)
		}

		return parts.joined(separator: " ")
	}
}
