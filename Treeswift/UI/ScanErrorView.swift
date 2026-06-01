//
//  ScanErrorView.swift
//  Treeswift
//
//  Scrollable build/scan error display with full log context
//

import SwiftUI

struct ScanErrorView: View {
	let errorMessage: String

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 6) {
				Image(systemName: "xmark.circle.fill")
					.foregroundStyle(.red)
				Text("Build / Scan Error")
					.fontWeight(.semibold)
					.foregroundStyle(.red)
				Spacer()
			}
			.padding(.horizontal, 12)
			.padding(.top, 10)
			.padding(.bottom, 6)

			Divider()
				.overlay(Color.red.opacity(0.3))

			ScrollView([.vertical, .horizontal]) {
				Text(errorMessage)
					.foregroundStyle(.primary)
					.font(.system(.caption, design: .monospaced))
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(12)
			}
			.frame(minHeight: 120, maxHeight: 400)
		}
		.background(Color.red.opacity(0.06))
		.clipShape(.rect(cornerRadius: 8))
		.overlay(
			RoundedRectangle(cornerRadius: 8)
				.strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
		)
		.padding()
	}
}
