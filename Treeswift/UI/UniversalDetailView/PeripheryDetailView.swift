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
	let sourceGraph: (any SourceGraphProtocol)?
	let projectPath: String?
	@Binding var filterState: FilterState

	private var projectRoot: String? {
		projectRootPath(from: projectPath)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			switch node {
			case let .folder(folder):
				FolderDetailView(folder: folder, projectRoot: projectRoot)
			case let .file(file):
				FileDetailView(
					file: file,
					scanResults: scanResults,
					sourceGraph: sourceGraph,
					projectRoot: projectRoot,
					filterState: $filterState
				)
			}
		}
	}
}

private struct FolderDetailView: View {
	let folder: FolderNode
	let projectRoot: String?

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(folder.name)
				.font(.title2)
				.bold()

			HStack(spacing: 6) {
				Text(relativePath(folder.path, to: projectRoot))
					.font(.caption)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)

				Button("Reveal in Finder", systemImage: "arrow.right.circle.fill", action: revealInFinder)
					.labelStyle(.iconOnly)
					.foregroundStyle(.secondary)
					.buttonStyle(.plain)
					.help("Reveal in Finder")
			}

			Text("\(folder.children.count) items")
				.font(.body)
				.foregroundStyle(.secondary)
		}
	}

	func revealInFinder() {
		openFolderInFinder(path: folder.path)
	}
}

private struct FileDetailView: View {
	let file: FileNode
	let scanResults: [ScanResult]
	let sourceGraph: (any SourceGraphProtocol)?
	let projectRoot: String?
	@Binding var filterState: FilterState
	@Environment(FileInspectorState.self) var inspectorState

	var fileWarnings: [ScanResult] {
		scanResults.filter { result in
			let location = ScanResultHelper.location(from: result.declaration)
			return location.file.path.string == file.path
		}
	}

	var body: some View {
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
				.bold()
				.textSelection(.enabled)

			HStack(spacing: 6) {
				Text(relativePath(file.path, to: projectRoot))
					.font(.caption)
					.foregroundStyle(.secondary)
					.textSelection(.enabled)

				Button("Open in Xcode", systemImage: "arrow.right.circle.fill", action: openInXcode)
					.labelStyle(.iconOnly)
					.foregroundStyle(.secondary)
					.buttonStyle(.plain)
					.help("Open in Xcode")
			}

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

	func openInXcode() {
		openFileInEditor(path: file.path)
	}
}
