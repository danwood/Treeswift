//
//  SearchMatchEngine.swift
//  Treeswift
//
//  Shared search/matching logic for tree node searching across both
//  TreeNode (Periphery tab) and CategoriesNode (category tabs)
//

import Foundation

enum SearchMatchEngine {
	struct SearchResult: Identifiable, Sendable {
		let nodeID: String
		let name: String
		let matchType: MatchType
		let icon: TreeIcon
		let tab: ResultsTab
		let parentIDs: [String]
		let matchQuality: MatchQuality
		let isView: Bool?

		// Unique identifier combining tab and node ID for ForEach stability
		var id: String { "\(tab.rawValue):\(nodeID)" }
	}

	enum MatchType: Sendable {
		case fileName
		case symbolName
	}

	enum MatchQuality: Comparable, Sendable {
		case prefixMatch
		case partialMatch
	}

	// MARK: - TreeNode Search (Periphery Tab)

	/**
	 Searches TreeNode hierarchy for names matching the query.
	 Searches both file names and folder names.
	 When visibleOnly is true, only searches nodes whose parents are expanded.
	 */
	static func searchTreeNodes(
		_ query: String,
		in nodes: [TreeNode],
		expandedIDs: Set<String>,
		visibleOnly: Bool
	) -> [SearchResult] {
		var results: [SearchResult] = []
		searchTreeNodesRecursive(
			query: query.lowercased(),
			nodes: nodes,
			expandedIDs: expandedIDs,
			visibleOnly: visibleOnly,
			currentParentIDs: [],
			results: &results
		)
		return results.sorted()
	}

	private static func searchTreeNodesRecursive(
		query: String,
		nodes: [TreeNode],
		expandedIDs: Set<String>,
		visibleOnly: Bool,
		currentParentIDs: [String],
		results: inout [SearchResult]
	) {
		for node in nodes {
			switch node {
			case let .folder(folder):
				let lowercaseName = folder.name.lowercased()
				if let quality = matchQuality(name: lowercaseName, query: query) {
					results.append(SearchResult(
						nodeID: folder.id,
						name: folder.name,
						matchType: .fileName,
						icon: .systemImage("folder"),
						tab: .periphery,
						parentIDs: currentParentIDs,
						matchQuality: quality,
						isView: nil
					))
				}
				// Recurse into children if not in visible-only mode, or if this folder is expanded
				if !visibleOnly || expandedIDs.contains(folder.id) {
					searchTreeNodesRecursive(
						query: query,
						nodes: folder.children,
						expandedIDs: expandedIDs,
						visibleOnly: visibleOnly,
						currentParentIDs: currentParentIDs + [folder.id],
						results: &results
					)
				}

			case let .file(file):
				let lowercaseName = file.name.lowercased()
				if let quality = matchQuality(name: lowercaseName, query: query) {
					results.append(SearchResult(
						nodeID: file.id,
						name: file.name,
						matchType: .fileName,
						icon: .systemImage("doc"),
						tab: .periphery,
						parentIDs: currentParentIDs,
						matchQuality: quality,
						isView: nil
					))
				}
			}
		}
	}

	// MARK: - CategoriesNode Search (Category Tabs)

	/**
	 Searches CategoriesNode hierarchy for names matching the query.
	 Searches declaration display names, section titles, and synthetic root titles.
	 When visibleOnly is true, only searches nodes whose parents are expanded.
	 */
	static func searchCategoriesNodes(
		_ query: String,
		in section: CategoriesNode?,
		tab: ResultsTab,
		expandedIDs: Set<String>,
		visibleOnly: Bool
	) -> [SearchResult] {
		guard let section else { return [] }
		var results: [SearchResult] = []
		searchCategoriesNodesRecursive(
			query: query.lowercased(),
			nodes: [section],
			tab: tab,
			expandedIDs: expandedIDs,
			visibleOnly: visibleOnly,
			currentParentIDs: [],
			results: &results
		)
		return results.sorted()
	}

	private static func searchCategoriesNodesRecursive(
		query: String,
		nodes: [CategoriesNode],
		tab: ResultsTab,
		expandedIDs: Set<String>,
		visibleOnly: Bool,
		currentParentIDs: [String],
		results: inout [SearchResult]
	) {
		for node in nodes {
			switch node {
			case let .section(section):
				let lowercaseTitle = section.title.lowercased()
				if let quality = matchQuality(name: lowercaseTitle, query: query) {
					results.append(SearchResult(
						nodeID: section.id.rawValue,
						name: section.title,
						matchType: .symbolName,
						icon: .systemImage("folder"),
						tab: tab,
						parentIDs: currentParentIDs,
						matchQuality: quality,
						isView: nil
					))
				}
				if !visibleOnly || expandedIDs.contains(section.id.rawValue) {
					searchCategoriesNodesRecursive(
						query: query,
						nodes: section.children,
						tab: tab,
						expandedIDs: expandedIDs,
						visibleOnly: visibleOnly,
						currentParentIDs: currentParentIDs + [section.id.rawValue],
						results: &results
					)
				}

			case let .declaration(decl):
				let lowercaseName = decl.displayName.lowercased()
				if let quality = matchQuality(name: lowercaseName, query: query) {
					results.append(SearchResult(
						nodeID: decl.id,
						name: decl.displayName,
						matchType: .symbolName,
						icon: decl.typeIcon,
						tab: tab,
						parentIDs: currentParentIDs,
						matchQuality: quality,
						isView: decl.isView
					))
				} else if let fileName = decl.locationInfo.fileName {
					// Only check file name as a fallback when symbol name didn't match
					let lowercaseFileName = fileName.lowercased()
					if let quality = matchQuality(name: lowercaseFileName, query: query) {
						results.append(SearchResult(
							nodeID: decl.id,
							name: fileName,
							matchType: .fileName,
							icon: .systemImage("doc"),
							tab: tab,
							parentIDs: currentParentIDs,
							matchQuality: quality,
							isView: decl.isView
						))
					}
				}
				if !visibleOnly || expandedIDs.contains(decl.id) {
					searchCategoriesNodesRecursive(
						query: query,
						nodes: decl.children,
						tab: tab,
						expandedIDs: expandedIDs,
						visibleOnly: visibleOnly,
						currentParentIDs: currentParentIDs + [decl.id],
						results: &results
					)
				}

			case let .syntheticRoot(root):
				let lowercaseTitle = root.title.lowercased()
				if let quality = matchQuality(name: lowercaseTitle, query: query) {
					results.append(SearchResult(
						nodeID: root.id,
						name: root.title,
						matchType: .symbolName,
						icon: root.icon,
						tab: tab,
						parentIDs: currentParentIDs,
						matchQuality: quality,
						isView: nil
					))
				}
				if !visibleOnly || expandedIDs.contains(root.id) {
					searchCategoriesNodesRecursive(
						query: query,
						nodes: root.children,
						tab: tab,
						expandedIDs: expandedIDs,
						visibleOnly: visibleOnly,
						currentParentIDs: currentParentIDs + [root.id],
						results: &results
					)
				}
			}
		}
	}

	// MARK: - Match Quality

	/**
	 Determines match quality for a name against a query.
	 Returns nil if no match, .prefixMatch if name starts with query,
	 .partialMatch if name contains query elsewhere.
	 Both name and query should already be lowercased.
	 */
	private static func matchQuality(name: String, query: String) -> MatchQuality? {
		if name.hasPrefix(query) {
			.prefixMatch
		} else if name.contains(query) {
			.partialMatch
		} else {
			nil
		}
	}
}

// MARK: - Sorting Support

extension SearchMatchEngine.SearchResult: Comparable {
	static func < (lhs: SearchMatchEngine.SearchResult, rhs: SearchMatchEngine.SearchResult) -> Bool {
		if lhs.matchQuality != rhs.matchQuality {
			// Prefix matches come first (prefixMatch < partialMatch in Comparable)
			return lhs.matchQuality < rhs.matchQuality
		}
		// Within same quality, shorter names first (closer match), then alphabetical
		if lhs.name.count != rhs.name.count {
			return lhs.name.count < rhs.name.count
		}
		return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
	}
}
