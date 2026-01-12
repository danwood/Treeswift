//
//  LayoutConstants.swift
//  Treeswift
//
//  Layout width constants for three-column NavigationSplitView
//

import SwiftUI

enum LayoutConstants {
	// Sidebar column (configuration list)
	static let sidebarMinWidth: CGFloat = 200
	static let sidebarIdealWidth: CGFloat = 250
	static let sidebarMaxWidth: CGFloat = 400

	// Content column (configuration form + scan results)
	static let contentColumnMinWidth: CGFloat = 500
	static let contentColumnIdealWidth: CGFloat = 600
	static let contentColumnMaxWidth: CGFloat = 900

	// Detail column (selected item details)
	static let detailColumnMinWidth: CGFloat = 250
	static let detailColumnIdealWidth: CGFloat = 350
	static let detailColumnMaxWidth: CGFloat = 500

	// Window size (fits all three columns at ideal widths)
	static let windowDefaultWidth: CGFloat = sidebarIdealWidth + contentColumnIdealWidth + detailColumnIdealWidth
	static let windowDefaultHeight: CGFloat = 700
}
