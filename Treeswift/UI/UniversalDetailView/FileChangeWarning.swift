//
//  FileChangeWarning.swift
//  Treeswift
//
//  Warning banner shown when inspected file has changed externally
//

import SwiftUI

struct FileChangeWarning: View {
	let message: String
	let detail: String

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.orange)
					.font(.title3)

				VStack(alignment: .leading, spacing: 4) {
					Text(message)
						.font(.headline)
						.foregroundStyle(.primary)

					Text(detail)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.orange.opacity(0.1))
		.clipShape(RoundedRectangle(cornerRadius: 8))
		.overlay(
			RoundedRectangle(cornerRadius: 8)
				.stroke(Color.orange.opacity(0.3), lineWidth: 1)
		)
	}
}
