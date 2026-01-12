//
//  DetailUsageSection.swift
//  Treeswift
//
//  Detail section showing file usage statistics and reference patterns
//

import SwiftUI

struct DetailUsageSection: View {
	let statistics: FileStatistics
	let usageBadge: UsageBadge?

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Usage")
				.font(.headline)

			VStack(alignment: .leading, spacing: 6) {
				// Reference statistics
				if statistics.symbolCount > 0 {
					referenceRow
				} else {
					HStack(spacing: 6) {
						Image(systemName: "questionmark.circle")
							.foregroundStyle(.secondary)
						Text("No analyzable symbols")
							.foregroundStyle(.secondary)
					}
				}

				// Unused file warning
				if usageBadge?.isWarning == true {
					HStack(spacing: 6) {
						Image(systemName: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
						Text("Unused file: symbols are not referenced by any other file")
							.foregroundStyle(.orange)
					}
				}

				// Usage badge summary
				if let badge = usageBadge {
					HStack(spacing: 6) {
						Image(systemName: badge.isPositive ? "checkmark.circle.fill" : (badge.isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill"))
							.foregroundStyle(badge.isPositive ? .green : (badge.isWarning ? .orange : .secondary))
						Text(badge.text)
							.foregroundStyle(badge.isPositive ? .green : (badge.isWarning ? .orange : .secondary))
					}
				}
			}
		}
		.padding(.vertical, 4)
	}

	@ViewBuilder
	private var referenceRow: some View {
		let hasCrossFolderRefs = statistics.externalFileCount > 0
		let hasSameFolderRefs = statistics.sameFolderFileCount > 0

		if statistics.isFolderPrivate {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Image(systemName: "folder")
						.foregroundStyle(.green)
					Text("Folder-private")
						.foregroundStyle(.primary)
				}
				// Show referencing file names below
				Text(sameFolderReferencesText)
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.leading, 22)
			}
		} else if hasCrossFolderRefs {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Image(systemName: "arrow.triangle.branch")
						.foregroundStyle(.primary)
					Text(crossFolderSummaryText)
				}
				// Show referencing folder names below
				if !statistics.referencingFolders.isEmpty {
					Text(crossFolderReferencesText)
						.font(.caption)
						.foregroundStyle(.secondary)
						.padding(.leading, 22)
				}
			}
		} else if hasSameFolderRefs {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Image(systemName: "folder")
						.foregroundStyle(.primary)
					Text("Used in same folder")
				}
				Text(sameFolderReferencesText)
					.font(.caption)
					.foregroundStyle(.secondary)
					.padding(.leading, 22)
			}
		}
	}

	private var crossFolderSummaryText: String {
		if statistics.folderReferenceCount >= 2 {
			return "Cross-folder: \(statistics.folderReferenceCount) folders"
		} else if statistics.externalFileCount > 1 {
			return "Cross-folder: \(statistics.externalFileCount) files"
		} else {
			return "Cross-folder: 1 file"
		}
	}

	private var crossFolderReferencesText: String {
		let folders = statistics.referencingFolders
		let folderList = folders.map { "\($0)/" }.joined(separator: ", ")
		return "← \(folderList)"
	}

	private var sameFolderReferencesText: String {
		let files = statistics.sameFolderFileNames
		if files.count <= 2 {
			let fileList = files.joined(separator: ", ")
			return "← \(fileList)"
		} else {
			return "← \(files.count) files"
		}
	}
}
