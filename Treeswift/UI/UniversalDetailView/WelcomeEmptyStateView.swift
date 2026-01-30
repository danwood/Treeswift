//
//  WelcomeEmptyStateView.swift
//  Treeswift
//
//  Welcome message shown before any scan is run
//

import SwiftUI

struct WelcomeEmptyStateView: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Welcome to Treeswift")
				.font(.title)
				.fontWeight(.semibold)

			Text("Configure your project settings and run a scan to begin analysis.")
				.font(.body)
				.foregroundStyle(.secondary)

			Divider()
				.padding(.vertical, 8)

			VStack(alignment: .leading, spacing: 12) {
				Text("Getting Started:")
					.font(.headline)

				BulletPoint(text: "Select or create a configuration in the sidebar")
				BulletPoint(text: "Configure your project path and schemes")
				BulletPoint(text: "Click 'Build & Scan' to analyze your code")
				BulletPoint(text: "Explore results in the Periphery, Categories, etc. tabs")
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.padding(40)
	}
}

private struct BulletPoint: View {
	let text: String

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			Text("•")
				.foregroundStyle(.secondary)
			Text(text)
				.foregroundStyle(.secondary)
		}
	}
}
