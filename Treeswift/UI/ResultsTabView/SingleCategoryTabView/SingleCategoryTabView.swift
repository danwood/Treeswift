//
//  SingleCategoryTabView.swift
//  Treeswift
//
//  Displays a single category section with its title and hierarchical content
//
//  NOTE: AttributeGraph cycle warnings
//  This view generates benign AttributeGraph cycle warnings during initial render when
//  multiple instances (7 category tabs) update simultaneously. The warnings appear after
//  scan completion when results are first displayed. Root causes:
//  - FocusClaimingView (NSViewRepresentable) updates trigger cascading view updates
//  - SwiftUI's dependency tracker conservatively flags this as a potential cycle
//  These warnings don't cause functional issues, performance problems, or UI glitches.
//  Computed properties are already pre-evaluated at body start to minimize re-evaluation.
//

import Flow
import SwiftUI

extension EnvironmentValues {
	@Entry var showOnlyViews: Bool = false
	@Entry var showFileName: Bool = false
	@Entry var showFileInfo: Bool = false
	@Entry var showCodeSize: Bool = false
	@Entry var showConformance: Bool = false
	@Entry var showPath: Bool = false
}

struct SingleCategoryTabView: View {
	let section: CategoriesNode?
	@Binding var showOnlyViews: Bool
	@Binding var showFileName: Bool
	@Binding var showFileInfo: Bool
	@Binding var showCodeSize: Bool
	@Binding var showPath: Bool
	@Binding var showConformance: Bool
	@State private var expandedIDs: Set<String> = []
	@Binding var selectedID: String?
	@State private var hasAppearedOnce: Bool = false
	@State private var claimFocusTrigger: Bool = false
	var projectRootPath: String?
	let showToggle: Bool

	private var sectionNode: SectionNode? {
		guard case let .section(s) = section else { return nil }
		return s
	}

	private var visibleItems: [String] {
		guard section != nil else { return [] }
		return TreeKeyboardNavigation.buildVisibleItemList(
			nodes: filteredChildren,
			expandedIDs: expandedIDs
		)
	}

	private var copyableText: String? {
		guard let selectedID,
		      let section,
		      let node = TreeNodeFinder.findCategoriesNode(withID: selectedID, in: [section]) else {
			return nil
		}
		return TreeCopyFormatter.formatForCopy(
			node: node,
			includeDescendants: true,
			indentLevel: 0
		)
	}

	var body: some View {
		Group {
			// Pre-evaluate computed properties once to minimize AttributeGraph dependency cycles
			let children = filteredChildren
			let visible = visibleItems
			let copyText = copyableText

			if section == nil {
				ProgressView("Loading…")
					.padding()
			} else if let sectionNode {
				VStack(alignment: .leading, spacing: 12) {
					// Section title at top (not in disclosure group)
					Text(sectionNode.title)
						.font(.system(.title3, design: .default))
						.bold()
						.foregroundStyle(.primary)
						.padding(.horizontal)

					// Show toggle for tree tab only
					if showToggle {
						VStack(alignment: .leading) {
							HFlow(itemSpacing: 10, rowSpacing: 8) {
								Toggle("Views Only", isOn: $showOnlyViews)

								Toggle("File Name", isOn: $showFileName)
								Toggle("File Info", isOn: $showFileInfo)
								Toggle("Conformance", isOn: $showConformance)
								Toggle("Path", isOn: $showPath)
								Toggle("Code Size", isOn: $showCodeSize)
							}
							.toggleStyle(.switch)
							.controlSize(.small)

							DisclosureGroup("Legend") {
								HStack(alignment: .top, spacing: 20) {
									VStack(alignment: .leading, spacing: 4) {
										Text("🔷   Main App entry point (@main)")
										Text("🖼️   SwiftUI View")
										Text("🟤   AppKit class (inherits from NS* type)")
										Text("🟦   Struct")
										Text("🔵   Class")
										Text("🚦   Enum")
										Text("📜   Protocol")
										Text("⚡️   Function")
										Text("🫥   Property or Variable")
										Text("🏷️   Type alias")
										Text("🔮   Macro")
										Text("⚖️   Precedence group")
										Text("🧩   Extension")
										Text("⬜️   Other declaration type")
										Text("⚠️   No symbols found")
									}
									VStack(alignment: .leading, spacing: 4) {
										Text("📎   Embedded in parent type")
										Text("↖️   In same file as parent type")
										Text("\(Image(systemName: "folder"))   Folderprivate folder")
									}
								}

								.padding()
								.background(.foreground.opacity(0.05))
								.border(Color.secondary, width: 0.5)
							}
							.padding(.horizontal, 20)
						}
					}
					// Display children
					LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
						ForEach(children, id: \.id) { child in
							CategoriesNodeView(
								node: child,
								expandedIDs: $expandedIDs,
								selectedID: $selectedID,
								indentLevel: 0,
								projectRootPath: projectRootPath
							)
							.transition(.opacity)
						}
					}
				}
				.focusableTreeNavigation(
					selectedID: $selectedID,
					visibleItems: visible,
					claimFocusTrigger: $claimFocusTrigger
				)
				.focusedValue(\.copyableText, copyText)
				.onCopyCommand {
					guard let text = copyText else { return [] }
					return [NSItemProvider(object: text as NSString)]
				}
				.animation(.easeInOut(duration: 0.3), value: showOnlyViews)
				.onAppear {
					if expandedIDs.isEmpty {
						expandAllNodes()
					}
				}
				.task {
					guard !hasAppearedOnce else { return }
					hasAppearedOnce = true
					try? await Task.sleep(for: .milliseconds(50))
					claimFocusTrigger.toggle()
				}

			} else {
				EmptyView()
			}
		}
		.environment(\.showCodeSize, showCodeSize)
		.environment(\.showPath, showPath)
		.environment(\.showFileInfo, showFileInfo)
		.environment(\.showOnlyViews, showOnlyViews)
		.environment(\.showFileName, showFileName)
		.environment(\.showConformance, showConformance)
	}

	private var filteredChildren: [CategoriesNode] {
		guard let sectionNode else { return [] }

		if !showOnlyViews || !showToggle {
			return sectionNode.children
		}

		// Single seenIDs set shared across all children to prevent duplicates
		// when the same shared component appears under multiple parents
		var seenIDs = Set<String>()
		return sectionNode.children.flatMap { filterNodeForViews($0, seenIDs: &seenIDs) }
	}

	/**
	 Filters nodes to show only Views when "Views Only" toggle is enabled.
	 Tracks seen IDs to avoid duplicates when the same shared component
	 appears under multiple non-View parents that get flattened away.
	 */
	private func filterNodeForViews(_ node: CategoriesNode, seenIDs: inout Set<String>) -> [CategoriesNode] {
		switch node {
		case var .section(section):
			if section.id == .hierarchy {
				var flattenedChildren: [CategoriesNode] = []
				for child in section.children {
					flattenViewChildren(child, into: &flattenedChildren, seenIDs: &seenIDs)
				}
				section.children = flattenedChildren
				return [.section(section)]
			}
			return [node]

		case let .declaration(decl):
			if decl.isView {
				var mutableDecl = decl
				var flattenedChildren: [CategoriesNode] = []
				for child in decl.children {
					flattenViewChildren(child, into: &flattenedChildren, seenIDs: &seenIDs)
				}
				mutableDecl.children = flattenedChildren
				return [.declaration(mutableDecl)]
			} else {
				var promoted: [CategoriesNode] = []
				for child in decl.children {
					flattenViewChildren(child, into: &promoted, seenIDs: &seenIDs)
				}
				return promoted
			}

		case var .syntheticRoot(root):
			var flattenedChildren: [CategoriesNode] = []
			for child in root.children {
				flattenViewChildren(child, into: &flattenedChildren, seenIDs: &seenIDs)
			}
			root.children = flattenedChildren
			return [.syntheticRoot(root)]
		}
	}

	/**
	 Recursively flattens view hierarchy, keeping only View nodes.
	 Skips nodes whose ID has already been seen to prevent duplicate entries
	 when the same shared component is referenced from multiple parents.
	 */
	private func flattenViewChildren(
		_ node: CategoriesNode,
		into result: inout [CategoriesNode],
		seenIDs: inout Set<String>
	) {
		switch node {
		case let .section(section):
			if section.id == .hierarchy {
				for child in section.children {
					flattenViewChildren(child, into: &result, seenIDs: &seenIDs)
				}
			} else {
				result.append(node)
			}

		case let .declaration(decl):
			if decl.isView {
				guard seenIDs.insert(decl.id).inserted else { return }
				var mutableDecl = decl
				var flattenedChildren: [CategoriesNode] = []
				for child in decl.children {
					flattenViewChildren(child, into: &flattenedChildren, seenIDs: &seenIDs)
				}
				mutableDecl.children = flattenedChildren
				result.append(.declaration(mutableDecl))
			} else {
				for child in decl.children {
					flattenViewChildren(child, into: &result, seenIDs: &seenIDs)
				}
			}

		case var .syntheticRoot(root):
			var flattenedChildren: [CategoriesNode] = []
			for child in root.children {
				flattenViewChildren(child, into: &flattenedChildren, seenIDs: &seenIDs)
			}
			root.children = flattenedChildren
			result.append(.syntheticRoot(root))
		}
	}

	/**
	 Expands all nodes in the section on first appearance
	 */
	private func expandAllNodes() {
		guard let section else { return }
		var idsToExpand = Set<String>()
		collectAllExpandableIDs(from: [section], into: &idsToExpand)
		Task { @MainActor in
			expandedIDs = idsToExpand
		}
	}

	/**
	 Recursively collects all expandable node IDs
	 */
	private func collectAllExpandableIDs(from nodes: [CategoriesNode], into set: inout Set<String>) {
		for node in nodes {
			switch node {
			case let .section(section):
				set.insert(section.id.rawValue)
				collectAllExpandableIDs(from: section.children, into: &set)
			case let .syntheticRoot(root):
				set.insert(root.id)
				collectAllExpandableIDs(from: root.children, into: &set)
			case let .declaration(decl):
				if !decl.children.isEmpty {
					set.insert(decl.id)
					collectAllExpandableIDs(from: decl.children, into: &set)
				}
			}
		}
	}
}
