//
//  LineSizeGraph.swift
//  Treeswift
//
//  Created by Dan Wood on 1/21/26.
//

import SwiftUI

struct LineSizeGraph: View {
	let line: Int
	let endLine: Int?

	private let maxCount = 200

	var body: some View {
		let rawFraction: CGFloat = if let endLine {
			CGFloat(endLine - line) / CGFloat(maxCount)
		} else {
			0.0
		}

		let cappedFraction = max(min(rawFraction, 1.0), 0.0)
		let isOverflow = rawFraction > 1.0

		let foreground: Color = isOverflow ? .red : .accentColor
		let background = Color.gray.opacity(0.2)

		GeometryReader { proxy in
			ZStack(alignment: .trailing) {
				ZStack(alignment: .leading) {
					background
					foreground
						.frame(width: proxy.size.width * cappedFraction)
				}
				.frame(height: 6.0)
				.clipShape(RoundedRectangle(cornerRadius: 3.0))

				if isOverflow {
					Circle()
						.foregroundStyle(foreground)
						.frame(width: 10, height: 10)
				}
			}
		}
	}
}

#Preview {
	VStack {
		LineSizeGraph(line: 100, endLine: 150)
		LineSizeGraph(line: 100, endLine: 299)
		LineSizeGraph(line: 100, endLine: 300)
		LineSizeGraph(line: 100, endLine: 301)
		LineSizeGraph(line: 100, endLine: 400)
	}
}
