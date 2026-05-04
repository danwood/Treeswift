//
//	CacheRestoreProgressView.swift
//	Treeswift
//
//	Shown at startup while ScanStateManager loads cached scan results from disk.
//

import SwiftUI

/// Wrapper that observes ScanStateManager and feeds live values into CacheRestoreProgressView.
struct CacheRestoreLiveView: View {
	var scanStateManager: ScanStateManager
	var onCancel: () -> Void

	var body: some View {
		CacheRestoreProgressView(
			status: scanStateManager.cacheRestoreStatus,
			loaded: scanStateManager.cacheRestoreLoaded,
			total: scanStateManager.cacheRestoreTotal,
			onCancel: onCancel
		)
	}
}

struct CacheRestoreProgressView: View {
	let status: String
	let loaded: Int
	let total: Int
	let onCancel: () -> Void

	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: "externaldrive.fill")
				.font(.system(size: 32))
				.foregroundStyle(.secondary)

			Text("Loading Cached Results")
				.font(.headline)

			ProgressView(value: total > 0 ? Double(loaded) / Double(total) : 0)
				.progressViewStyle(.linear)
				.frame(width: 260)

			Text(status)
				.font(.caption)
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.frame(width: 260)

			Text("\(loaded) of \(total)")
				.font(.caption2)
				.foregroundStyle(.tertiary)
				.opacity(total > 0 ? 1 : 0)

			Button("Cancel") {
				onCancel()
			}
			.buttonStyle(.bordered)
		}
		.padding(28)
		.frame(width: 320)
	}
}
