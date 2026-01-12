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
//  - Multiple instances share the @AppStorage("showOnlyViews") binding via parent view
//  - FocusClaimingView (NSViewRepresentable) updates trigger cascading view updates
//  - SwiftUI's dependency tracker conservatively flags this as a potential cycle
//  These warnings don't cause functional issues, performance problems, or UI glitches.
//  Computed properties are already pre-evaluated at body start to minimize re-evaluation.
//

import SwiftUI

struct SingleCategoryTabView: View {
	let section: CategoriesNode?
	@Binding var showOnlyViews: Bool
	@State private var expandedIDs: Set<String> = []
	@Binding var selectedID: String?
	@State private var hasAppearedOnce: Bool = false
	@State private var claimFocusTrigger: Bool = false
	var projectRootPath: String?
	let showToggle: Bool

	private var sectionNode: SectionNode? {
		guard case .section(let s) = section else { return nil }
		return s
	}

	private var visibleItems: [String] {
		guard section != nil else { return [] }
		return TreeKeyboardNavigation.buildVisibleItemList(
			nodes: filteredChildren,
			expandedIDs: expandedIDs
		)
	}

	var copyableText: String? {
		guard let selectedID = selectedID,
			  let section = section,
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
		// Pre-evaluate computed properties once to minimize AttributeGraph dependency cycles
		let children = filteredChildren
		let visible = visibleItems
		let copyText = copyableText

		if section == nil {
			return AnyView(
				ProgressView("Loading…")
					.padding()
			)
		} else if let sectionNode = sectionNode {
			return AnyView(
				VStack(alignment: .leading, spacing: 12) {
					// Section title at top (not in disclosure group)
					Text(sectionNode.title)
						.font(.system(.title3, design: .default))
						.fontWeight(.bold)
						.foregroundStyle(.primary)
						.padding(.horizontal)

					// Show toggle for tree tab only
					if showToggle {
						Toggle("Show only Views", isOn: Binding(
							get: { showOnlyViews },
							set: { newValue in
								withAnimation(.easeInOut(duration: 0.3)) {
									showOnlyViews = newValue
								}
							}
						))
						.toggleStyle(.switch)
						.controlSize(.small)
						.padding(.horizontal)
					}

					// Display children
					LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
						ForEach(children, id: \.id) { child in
							CategoriesNodeView(
								node: child,
								expandedIDs: $expandedIDs,
								selectedID: $selectedID,
								showOnlyViews: $showOnlyViews,
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

					if !hasAppearedOnce {
						hasAppearedOnce = true
						Task { @MainActor in
							try? await Task.sleep(for: .milliseconds(50))
							claimFocusTrigger.toggle()
						}
					}
				}
			)
		} else {
			return AnyView(EmptyView())
		}
	}

	private var filteredChildren: [CategoriesNode] {
		guard let sectionNode = sectionNode else { return [] }

		if !showOnlyViews || !showToggle {
			return sectionNode.children
		}

		// Apply filtering logic for Tree tab when "Show Only Views" is enabled
		return sectionNode.children.compactMap { filterNodeForViews($0) }
	}

	/**
	Filters nodes to show only Views when "Show Only Views" toggle is enabled
	*/
	private func filterNodeForViews(_ node: CategoriesNode) -> CategoriesNode? {
		switch node {
		case .section(var section):
			if section.id == .hierarchy {
				var flattenedChildren: [CategoriesNode] = []
				for child in section.children {
					flattenViewChildren(child, into: &flattenedChildren)
				}
				section.children = flattenedChildren
				return .section(section)
			}
			return node

		case .declaration(let decl):
			if decl.isView {
				var mutableDecl = decl
				var flattenedChildren: [CategoriesNode] = []
				for child in decl.children {
					flattenViewChildren(child, into: &flattenedChildren)
				}
				mutableDecl.children = flattenedChildren
				return .declaration(mutableDecl)
			} else {
				return nil
			}

		case .syntheticRoot(var root):
			var flattenedChildren: [CategoriesNode] = []
			for child in root.children {
				flattenViewChildren(child, into: &flattenedChildren)
			}
			root.children = flattenedChildren
			return .syntheticRoot(root)
		}
	}

	/**
	Recursively flattens view hierarchy, keeping only View nodes
	*/
	private func flattenViewChildren(_ node: CategoriesNode, into result: inout [CategoriesNode]) {
		switch node {
		case .section(let section):
			if section.id == .hierarchy {
				for child in section.children {
					flattenViewChildren(child, into: &result)
				}
			} else {
				result.append(node)
			}

		case .declaration(let decl):
			if decl.isView {
				var mutableDecl = decl
				var flattenedChildren: [CategoriesNode] = []
				for child in decl.children {
					flattenViewChildren(child, into: &flattenedChildren)
				}
				mutableDecl.children = flattenedChildren
				result.append(.declaration(mutableDecl))
			} else {
				for child in decl.children {
					flattenViewChildren(child, into: &result)
				}
			}

		case .syntheticRoot(var root):
			var flattenedChildren: [CategoriesNode] = []
			for child in root.children {
				flattenViewChildren(child, into: &flattenedChildren)
			}
			root.children = flattenedChildren
			result.append(.syntheticRoot(root))
		}
	}

	/**
	Expands all nodes in the section on first appearance
	*/
	private func expandAllNodes() {
		guard let section = section else { return }
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
			case .section(let section):
				set.insert(section.id.rawValue)
				collectAllExpandableIDs(from: section.children, into: &set)
			case .syntheticRoot(let root):
				set.insert(root.id)
				collectAllExpandableIDs(from: root.children, into: &set)
			case .declaration(let decl):
				if !decl.children.isEmpty {
					set.insert(decl.id)
					collectAllExpandableIDs(from: decl.children, into: &set)
				}
			}
		}
	}
}
