//
//  TreeLayoutEnvironment.swift
//  Treeswift
//
//  Environment key for tree layout constants
//

import SwiftUI

/**
 Observable object holding tree layout constants for real-time adjustment
 */
@Observable
@MainActor
final class TreeLayoutSettings {
	var indentPerLevel: CGFloat
	var leafNodeOffset: CGFloat
	var rowVerticalPadding: CGFloat
	var chevronWidth: CGFloat

	init(
		indentPerLevel: CGFloat = 20,
		leafNodeOffset: CGFloat = 20,
		rowVerticalPadding: CGFloat = 4,
		chevronWidth: CGFloat = 13
	) {
		self.indentPerLevel = indentPerLevel
		self.leafNodeOffset = leafNodeOffset
		self.rowVerticalPadding = rowVerticalPadding
		self.chevronWidth = chevronWidth
	}
}

extension EnvironmentValues {
	@Entry var treeLayoutSettings: TreeLayoutSettings = .init()
}
