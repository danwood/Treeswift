//
//  ScanErrorView.swift
//  Treeswift
//
//  Scrollable build/scan error display with full log context
//

import SwiftUI

struct ScanErrorView: View {
	let errorMessage: String
	// Full streamed build/scan log (toolchain, status lines, captured build output). Shown beneath the
	// error so the build output and errors are always visible — even when the thrown error stringifies
	// to little or nothing.
	var logLines: [String] = []

	private var trimmedError: String {
		errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var logText: String {
		logLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// What to render in the scrollable body: the error, then the log (de-duplicated if the error is
	// already the log's tail), and a clear placeholder if somehow both are empty.
	private var bodyText: String {
		var parts: [String] = []
		if !trimmedError.isEmpty {
			parts.append(trimmedError)
		}
		if !logText.isEmpty, !trimmedError.contains(logText), logText != trimmedError {
			parts.append("— Build / scan log —\n\(logText)")
		}
		if parts.isEmpty {
			return "The build or scan failed but produced no output to display."
		}
		return parts.joined(separator: "\n\n")
	}

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

			// Vertical scroll with wrapping. A horizontal ScrollView combined with
			// `.frame(maxWidth: .infinity)` made the Text fail to lay out — a build error's xcodebuild
			// command is a single ~50 KB line, and an unbounded width in an h-scroll renders nothing
			// (the blank pink box). Wrapping long lines keeps the actual error visible without scrolling
			// sideways. `lineLimit(nil)` + `fixedSize(vertical)` lets the Text grow to its full height.
			ScrollView(.vertical) {
				Text(bodyText)
					.foregroundStyle(.primary)
					.font(.system(.caption, design: .monospaced))
					.textSelection(.enabled)
					.lineLimit(nil)
					.fixedSize(horizontal: false, vertical: true)
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
