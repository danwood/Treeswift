//
//  PeripheryDetailView.swift
//  Treeswift
//
//  Detail view for selected items in Periphery tab
//

import AppKit
import PeripheryKit
import SourceGraph
import SwiftUI
import SystemPackage

struct PeripheryDetailView: View {
	let node: TreeNode
	let scanResults: [ScanResult]
	let sourceGraph: SourceGraph?
	let projectPath: String?
	@Binding var filterState: FilterState
	@Environment(FileInspectorState.self) private var inspectorState

	private var projectRoot: String? {
		projectRootPath(from: projectPath)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			switch node {
			case let .folder(folder):
				folderDetailView(folder)
			case let .file(file):
				fileDetailView(file)
			}
		}
	}

	private func folderDetailView(_ folder: FolderNode) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(folder.name)
				.font(.title2)
				.fontWeight(.semibold)

			HStack(spacing: 6) {
				Text(relativePath(folder.path, to: projectRoot))
					.font(.caption)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)

				Button(action: {
					openFolderInFinder(path: folder.path)
				}) {
					Image(systemName: "arrow.right.circle.fill")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
				.help("Reveal in Finder")
			}

			Text("\(folder.children.count) items")
				.font(.body)
				.foregroundStyle(.secondary)
		}
	}

	private func fileDetailView(_ file: FileNode) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			// File change warning banner
			if inspectorState.fileWasDeleted {
				FileChangeWarning(
					message: "File has been deleted",
					detail: "The file no longer exists. Please re-scan to update results."
				)
			} else if inspectorState.fileHasChanged {
				FileChangeWarning(
					message: "File has been modified",
					detail: "The file has changed since the last scan. Please re-scan for accurate results."
				)
			}

			Text(file.name)
				.font(.title2)
				.fontWeight(.semibold)
				.textSelection(.enabled)

			HStack(spacing: 6) {
				Text(relativePath(file.path, to: projectRoot))
					.font(.caption)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)

				Button(action: {
					openFileInEditor(path: file.path)
				}) {
					Image(systemName: "arrow.right.circle.fill")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
				.help("Open in Xcode")
			}

			// Fetch warnings from scanResults array instead of node children
			let fileWarnings = scanResults.filter { result in
				let declaration = result.declaration
				let location = ScanResultHelper.location(from: declaration)
				return location.file.path.string == file.path
			}

			// Show filtered periphery warnings section
			if !fileWarnings.isEmpty {
				Divider()
				DetailPeripheryWarningsSection(
					filePath: file.path,
					scanResults: fileWarnings,
					sourceGraph: sourceGraph,
					filterState: filterState
				)
				.padding(.vertical, 4)
			}
		}
	}
}
