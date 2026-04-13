//
//  ResultsHandler.swift
//  Treeswift
//

import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

enum ResultsHandler {
	static func handlePeripheryTree(server: AutomationServer, id: String) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let (treeNodes, isScanning, hasResults) = await MainActor.run {
			(state.treeNodes, state.isScanning, !state.scanResults.isEmpty)
		}

		if !hasResults, !isScanning {
			return .error("no scan results available", status: 404)
		}

		let response = treeNodes.map { TreeNodeResponse(from: $0) }
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		guard let data = try? encoder.encode(response) else {
			return .error("encoding failed", status: 500)
		}
		return Router.Response(statusCode: 200, body: data, contentType: "application/json")
	}

	static func handleCategory(server: AutomationServer, id: String, name: String) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let (section, isScanning, hasResults) = await MainActor.run { () -> (CategoriesNode?, Bool, Bool) in
			let section: CategoriesNode? = switch name {
			case "tree": state.treeSection
			case "viewExtensions": state.viewExtensionsSection
			case "shared": state.sharedSection
			case "orphans": state.orphansSection
			case "previewOrphans": state.previewOrphansSection
			case "bodyGetter": state.bodyGetterSection
			case "unattached": state.unattachedSection
			default: nil
			}
			return (section, state.isScanning, !state.scanResults.isEmpty)
		}

		if !hasResults, !isScanning {
			return .error("no scan results available", status: 404)
		}

		guard let section else {
			return .error("unknown category '\(name)'", status: 404)
		}

		let response = CategoriesNodeResponse(from: section)
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		guard let data = try? encoder.encode(response) else {
			return .error("encoding failed", status: 500)
		}
		return Router.Response(statusCode: 200, body: data, contentType: "application/json")
	}

	static func handleFilesTree(server: AutomationServer, id: String) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let (fileTreeNodes, isScanning, hasResults) = await MainActor.run {
			(state.fileTreeNodes, state.isScanning, !state.scanResults.isEmpty)
		}

		if !hasResults, !isScanning {
			return .error("no scan results available", status: 404)
		}

		let response = fileTreeNodes.map { FileBrowserNodeResponse(from: $0) }
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		guard let data = try? encoder.encode(response) else {
			return .error("encoding failed", status: 500)
		}
		return Router.Response(statusCode: 200, body: data, contentType: "application/json")
	}

	static func handleSummary(server: AutomationServer, id: String) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let (scanResults, isScanning) = await MainActor.run {
			(state.scanResults, state.isScanning)
		}

		if scanResults.isEmpty, !isScanning {
			return .error("no scan results available", status: 404)
		}

		return .json(ScanSummaryResponse(from: scanResults))
	}

	/**
	 Debug endpoint: returns raw scan results for a given file path.
	 Query param: ?file=/abs/path/to/File.swift
	 */
	static func handleRawResults(server: AutomationServer, id: String, filePath: String) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let scanResults = await MainActor.run { state.scanResults }
		if scanResults.isEmpty {
			return .error("no scan results available", status: 404)
		}

		nonisolated(unsafe) struct RawResult: Codable, Sendable {
			let annotation: String
			let name: String?
			let kind: String
			let line: Int
			let endLine: Int?
			let column: Int
		}

		let results = scanResults.compactMap { sr -> RawResult? in
			let decl = sr.declaration
			let loc = ScanResultHelper.location(from: decl)
			guard loc.file.path.string == filePath else { return nil }
			return RawResult(
				annotation: "\(sr.annotation)",
				name: decl.name,
				kind: "\(decl.kind)",
				line: loc.line,
				endLine: loc.endLine,
				column: loc.column
			)
		}.sorted { $0.line < $1.line }

		return .json(results)
	}
}
