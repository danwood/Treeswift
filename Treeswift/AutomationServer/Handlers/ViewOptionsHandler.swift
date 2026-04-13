//
//  ViewOptionsHandler.swift
//  Treeswift
//

import Foundation

private nonisolated struct ViewOptionsResponse: Codable, Sendable {
	let topLevelOnly: Bool
	let showUnused: Bool
	let showAssignOnly: Bool
	let showRedundantProtocol: Bool
	let showRedundantAccessControl: Bool
	let showSuperfluousIgnoreCommand: Bool
	let showClass: Bool
	let showEnum: Bool
	let showExtension: Bool
	let showFunction: Bool
	let showImport: Bool
	let showInitializer: Bool
	let showParameter: Bool
	let showProperty: Bool
	let showProtocol: Bool
	let showStruct: Bool
	let showTypealias: Bool
}

extension ViewOptionsResponse {
	@MainActor
	init(from filterState: FilterState) {
		topLevelOnly = filterState.topLevelOnly
		showUnused = filterState.showUnused
		showAssignOnly = filterState.showAssignOnly
		showRedundantProtocol = filterState.showRedundantProtocol
		showRedundantAccessControl = filterState.showRedundantAccessControl
		showSuperfluousIgnoreCommand = filterState.showSuperfluousIgnoreCommand
		showClass = filterState.showClass
		showEnum = filterState.showEnum
		showExtension = filterState.showExtension
		showFunction = filterState.showFunction
		showImport = filterState.showImport
		showInitializer = filterState.showInitializer
		showParameter = filterState.showParameter
		showProperty = filterState.showProperty
		showProtocol = filterState.showProtocol
		showStruct = filterState.showStruct
		showTypealias = filterState.showTypealias
	}
}

private nonisolated struct ViewOptionsRequest: Codable, Sendable {
	let topLevelOnly: Bool?
	let showUnused: Bool?
	let showAssignOnly: Bool?
	let showRedundantProtocol: Bool?
	let showRedundantAccessControl: Bool?
	let showSuperfluousIgnoreCommand: Bool?
	let showClass: Bool?
	let showEnum: Bool?
	let showExtension: Bool?
	let showFunction: Bool?
	let showImport: Bool?
	let showInitializer: Bool?
	let showParameter: Bool?
	let showProperty: Bool?
	let showProtocol: Bool?
	let showStruct: Bool?
	let showTypealias: Bool?
}

enum ViewOptionsHandler {
	static func handleGet(server: AutomationServer, id: String) async -> Router.Response {
		guard await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) != nil else {
			return .error("configuration not found", status: 404)
		}

		let response = await MainActor.run { ViewOptionsResponse(from: server.filterState) }
		return .json(response)
	}

	static func handleSet(server: AutomationServer, id: String, request: Router.Request) async -> Router.Response {
		guard await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) != nil else {
			return .error("configuration not found", status: 404)
		}

		guard let body = request.body,
		      let opts = try? JSONDecoder().decode(ViewOptionsRequest.self, from: body)
		else {
			return .error("invalid request body", status: 400)
		}

		let response = await MainActor.run { () -> ViewOptionsResponse in
			let f = server.filterState
			if let v = opts.topLevelOnly { f.topLevelOnly = v }
			if let v = opts.showUnused { f.showUnused = v }
			if let v = opts.showAssignOnly { f.showAssignOnly = v }
			if let v = opts.showRedundantProtocol { f.showRedundantProtocol = v }
			if let v = opts.showRedundantAccessControl { f.showRedundantAccessControl = v }
			if let v = opts.showSuperfluousIgnoreCommand { f.showSuperfluousIgnoreCommand = v }
			if let v = opts.showClass { f.showClass = v }
			if let v = opts.showEnum { f.showEnum = v }
			if let v = opts.showExtension { f.showExtension = v }
			if let v = opts.showFunction { f.showFunction = v }
			if let v = opts.showImport { f.showImport = v }
			if let v = opts.showInitializer { f.showInitializer = v }
			if let v = opts.showParameter { f.showParameter = v }
			if let v = opts.showProperty { f.showProperty = v }
			if let v = opts.showProtocol { f.showProtocol = v }
			if let v = opts.showStruct { f.showStruct = v }
			if let v = opts.showTypealias { f.showTypealias = v }
			return ViewOptionsResponse(from: f)
		}
		return .json(response)
	}
}
