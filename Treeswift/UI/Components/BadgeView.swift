//
//  BadgeView.swift
//  Treeswift
//
//  Badge component showing warning counts by type
//

import SwiftUI

struct Badge: Hashable, Identifiable, Sendable {
	let id = UUID()
	let letter: String
	let count: Int
	let swiftType: SwiftType
	let isUnused: Bool

	var color: NSColor {
		let baseColor = swiftType.color
		return isUnused ? baseColor : baseColor.lighter()
	}

	var textColor: NSColor {
		isUnused ? .white : .black
	}
}

struct BadgeView: View {
	let badge: Badge

	var body: some View {
		HStack(spacing: 0) {
			Text(badge.letter)
			if badge.count > 1 {
				Text(" ")
				Text("\(badge.count)")
			}
		}
		.font(.caption2)
		.foregroundStyle(Color(nsColor: badge.textColor))
		.padding(.vertical, 3)
		.padding(.horizontal, 6)
		.background(
			Capsule()
				.fill(Color(nsColor: badge.color))
		)
		.fixedSize()
		.drawingGroup()
	}
}

#Preview {
	HStack(spacing: 4) {
		BadgeView(badge: Badge(letter: "P", count: 43, swiftType: .property, isUnused: true))
		BadgeView(badge: Badge(letter: "P", count: 12, swiftType: .property, isUnused: false))
		BadgeView(badge: Badge(letter: "F", count: 8, swiftType: .function, isUnused: true))
	}
	.padding()
}
