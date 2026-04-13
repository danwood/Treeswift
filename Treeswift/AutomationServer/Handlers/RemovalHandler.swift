//
//  RemovalHandler.swift
//  Treeswift
//

import Foundation
import PeripheryKit
import SourceGraph

private nonisolated struct RemovalPreviewFile: Codable, Sendable {
	let filePath: String
	let deletableCount: Int
	let nonDeletableCount: Int
	let wouldDeleteFile: Bool
}

private nonisolated struct RemovalExecuteFile: Codable, Sendable {
	let filePath: String
	let deletedCount: Int
	let nonDeletableCount: Int
	let deleted: Bool
}

private nonisolated struct RemovalPreviewResponse: Codable, Sendable {
	let files: [RemovalPreviewFile]
	let totalDeletable: Int
	let totalNonDeletable: Int
}

private nonisolated struct RemovalExecuteResponse: Codable, Sendable {
	let files: [RemovalExecuteFile]
	let totalDeleted: Int
	let errors: [String]
}

private nonisolated struct RemovalRequest: Codable, Sendable {
	let nodeIds: [String]?
	let strategy: String?
}

enum RemovalHandler {
	static func handlePreview(server: AutomationServer, id: String, request: Router.Request) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let (scanResults, sourceGraph, treeNodes, isScanning) = await MainActor.run {
			(state.scanResults, state.sourceGraph, state.treeNodes, state.isScanning)
		}

		if scanResults.isEmpty, !isScanning {
			return .error("no scan results available", status: 404)
		}

		let removalRequest = parseRemovalRequest(request)
		let strategy = parseStrategy(removalRequest?.strategy)
		let targetFiles = collectFileNodes(from: treeNodes, ids: removalRequest?.nodeIds)

		// Pre-compute the batch deletion set so skipReferenced can treat cross-file
		// references within the batch as internal (not external).
		let batchDeletionSet = UnusedDependencyAnalyzer.buildBatchDeletionSet(
			filePaths: Set(targetFiles.map(\.path)),
			scanResults: scanResults
		)

		var previewFiles: [RemovalPreviewFile] = []
		var totalDeletable = 0
		var totalNonDeletable = 0

		let allUnused: Set<Declaration>? = sourceGraph?.unusedDeclarations
		for fileNode in targetFiles {
			let result = fileNode.computeRemoval(
				scanResults: scanResults,
				filterState: nil,
				sourceGraph: sourceGraph,
				strategy: strategy,
				allUnusedDeclarations: allUnused,
				batchDeletionSet: batchDeletionSet
			)
			switch result {
			case let .success(removal):
				let deletable = removal.deletionStats.deletedCount
				let nonDeletable = removal.deletionStats.nonDeletableCount
				totalDeletable += deletable
				totalNonDeletable += nonDeletable
				previewFiles.append(RemovalPreviewFile(
					filePath: fileNode.path,
					deletableCount: deletable,
					nonDeletableCount: nonDeletable,
					wouldDeleteFile: removal.shouldDeleteFile
				))
			case .failure:
				previewFiles.append(RemovalPreviewFile(
					filePath: fileNode.path,
					deletableCount: 0,
					nonDeletableCount: 0,
					wouldDeleteFile: false
				))
			}
		}

		return .json(RemovalPreviewResponse(
			files: previewFiles,
			totalDeletable: totalDeletable,
			totalNonDeletable: totalNonDeletable
		))
	}

	static func handleExecute(server: AutomationServer, id: String, request: Router.Request) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let (scanResults, sourceGraph, treeNodes, isScanning) = await MainActor.run {
			(state.scanResults, state.sourceGraph, state.treeNodes, state.isScanning)
		}

		if scanResults.isEmpty, !isScanning {
			return .error("no scan results available", status: 404)
		}

		let removalRequest = parseRemovalRequest(request)
		let strategy = parseStrategy(removalRequest?.strategy)
		let targetFiles = collectFileNodes(from: treeNodes, ids: removalRequest?.nodeIds)

		// Pre-compute the batch deletion set so skipReferenced can treat cross-file
		// references within the batch as internal (not external).
		let batchDeletionSet = UnusedDependencyAnalyzer.buildBatchDeletionSet(
			filePaths: Set(targetFiles.map(\.path)),
			scanResults: scanResults
		)

		var executeFiles: [RemovalExecuteFile] = []
		var totalDeleted = 0
		var errors: [String] = []
		var logLines: [String] = []

		let allUnused: Set<Declaration>? = sourceGraph?.unusedDeclarations

		// Pass 1 — Plan: compute all modifications without writing or mutating source graph
		var plans: [(fileNode: FileNode, removal: FileNode.RemovalResult)] = []
		for fileNode in targetFiles {
			let result = fileNode.computeRemoval(
				scanResults: scanResults,
				filterState: nil,
				sourceGraph: sourceGraph,
				strategy: strategy,
				allUnusedDeclarations: allUnused,
				batchDeletionSet: batchDeletionSet
			)
			switch result {
			case let .success(removal):
				plans.append((fileNode, removal))
			case let .failure(error):
				if (error as NSError).code != 2 {
					errors.append("Error processing \(fileNode.path): \(error.localizedDescription)")
					logLines.append("Error: \(fileNode.path): \(error.localizedDescription)")
				}
			}
		}

		// Pass 2 — Execute: write all planned results to disk
		// In the automation context, always write modified contents rather than
		// trashing files. This keeps the Xcode project intact (no missing file
		// references) so the build can verify whether remaining code compiles.
		for (fileNode, removal) in plans {
			let deletedCount = removal.deletionStats.deletedCount
			do {
				try removal.modifiedContents.write(toFile: fileNode.path, atomically: true, encoding: .utf8)
				SourceFileReader.invalidateCache(for: fileNode.path)
				if removal.shouldDeleteFile {
					logLines.append("Emptied file (would delete in UI): \(fileNode.path)")
				} else {
					logLines.append("Removed \(deletedCount) declaration(s) from \(fileNode.path)")
				}
			} catch {
				let errMsg = "Failed to write \(fileNode.path): \(error.localizedDescription)"
				errors.append(errMsg)
				logLines.append("Error: \(errMsg)")
			}

			totalDeleted += deletedCount
			executeFiles.append(RemovalExecuteFile(
				filePath: fileNode.path,
				deletedCount: deletedCount,
				nonDeletableCount: removal.deletionStats.nonDeletableCount,
				deleted: false
			))
		}

		await MainActor.run { state.removalLogBuffer = logLines }

		return .json(RemovalExecuteResponse(
			files: executeFiles,
			totalDeleted: totalDeleted,
			errors: errors
		))
	}

	static func handleLog(server: AutomationServer, id: String) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let logLines = await MainActor.run { state.removalLogBuffer }
		if logLines.isEmpty {
			return .error("no removal log available", status: 404)
		}
		return .text(logLines.joined(separator: "\n"))
	}

	private static func parseRemovalRequest(_ request: Router.Request) -> RemovalRequest? {
		guard let body = request.body else { return nil }
		return try? JSONDecoder().decode(RemovalRequest.self, from: body)
	}

	private static func parseStrategy(_ name: String?) -> RemovalStrategy {
		switch name {
		case "skipReferenced": .skipReferenced
		case "cascade": .cascade
		default: .forceRemoveAll
		}
	}

	private static func collectFileNodes(from treeNodes: [TreeNode], ids: [String]?) -> [FileNode] {
		let idSet = ids.map { Set($0) }
		var result: [FileNode] = []
		collectFileNodesRecursive(from: treeNodes, idSet: idSet, into: &result)
		return result
	}

	private static func collectFileNodesRecursive(
		from nodes: [TreeNode],
		idSet: Set<String>?,
		into result: inout [FileNode]
	) {
		for node in nodes {
			switch node {
			case let .folder(folder):
				collectFileNodesRecursive(from: folder.children, idSet: idSet, into: &result)
			case let .file(file):
				if let idSet {
					if idSet.contains(file.id) {
						result.append(file)
					}
				} else {
					result.append(file)
				}
			}
		}
	}
}
