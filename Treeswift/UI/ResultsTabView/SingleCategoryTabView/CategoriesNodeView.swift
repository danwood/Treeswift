//
//  CategoriesNodeView.swift
//  Treeswift
//
//  Created by Dan Wood on 11/30/25.
//

import Foundation
import SwiftUI

struct CategoriesNodeView: View {
	let node: CategoriesNode
	@Binding var expandedIDs: Set<String>
	@Binding var selectedID: String?
	@Binding var showOnlyViews: Bool
	var indentLevel: Int = 0
	var projectRootPath: String?

	var body: some View {
		switch node {
		case .section(let section):
			SectionRowView(section: section, expandedIDs: $expandedIDs, selectedID: $selectedID, showOnlyViews: $showOnlyViews, indentLevel: indentLevel, projectRootPath: projectRootPath)

		case .declaration(let decl):
			DeclarationRowView(declaration: decl, expandedIDs: $expandedIDs, selectedID: $selectedID, showOnlyViews: $showOnlyViews, indentLevel: indentLevel, projectRootPath: projectRootPath)

		case .syntheticRoot(let root):
			SyntheticRootRowView(root: root, expandedIDs: $expandedIDs, selectedID: $selectedID, showOnlyViews: $showOnlyViews, indentLevel: indentLevel, projectRootPath: projectRootPath)
		}
	}
}
