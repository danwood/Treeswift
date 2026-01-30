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
final class TreeLayoutSettings: Sendable {
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

private struct TreeLayoutSettingsKey: EnvironmentKey {
	static let defaultValue = TreeLayoutSettings()
}

extension EnvironmentValues {
	var treeLayoutSettings: TreeLayoutSettings {
		get { self[TreeLayoutSettingsKey.self] }
		set { self[TreeLayoutSettingsKey.self] = newValue }
	}
}

// FIXME: use modern syntax
