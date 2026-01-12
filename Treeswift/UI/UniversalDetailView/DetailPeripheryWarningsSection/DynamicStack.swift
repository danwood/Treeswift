//
//  DynamicStack.swift
//  Treeswift
//
//  Created by Dan Wood on 12/4/25.
//

import SwiftUI

// Courtesy https://www.swiftbysundell.com/articles/switching-between-swiftui-hstack-vstack/
struct DynamicStack<Content: View>: View {
	var axes: Axis.Set = [.horizontal, .vertical]
	var horizontalAlignment = HorizontalAlignment.center
	var verticalAlignment = VerticalAlignment.center
	var spacing: CGFloat?
	@ViewBuilder var content: () -> Content

	var body: some View {
		ViewThatFits(in: axes) {
			HStack(
				alignment: verticalAlignment,
				spacing: spacing,
				content: content
			)

			VStack(
				alignment: horizontalAlignment,
				spacing: spacing,
				content: content
			)
		}
	}
}
