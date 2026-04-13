//
//  ConfigurationsHandler.swift
//  Treeswift
//

import Foundation

enum ConfigurationsHandler {
	static func handleList(server: AutomationServer) async -> Router.Response {
		let configs = await MainActor.run { server.configManager.configurations }
		return encodeConfigs(configs)
	}

	static func handleGet(server: AutomationServer, id: String) async -> Router.Response {
		let config = await MainActor.run { () -> PeripheryConfiguration? in
			if let uuid = UUID(uuidString: id) {
				return server.configManager.configurations.first { $0.id == uuid }
			}
			let lower = id.lowercased()
			return server.configManager.configurations.first { $0.name.lowercased() == lower }
		}
		guard let config else {
			return .error("configuration not found", status: 404)
		}
		return encodeConfig(config)
	}

	static func handleCreate(server: AutomationServer, request: Router.Request) async -> Router.Response {
		guard let body = request.body else {
			return .error("request body required", status: 400)
		}
		do {
			// Inject a new UUID if the request body does not include one
			var jsonObj = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
			if jsonObj["id"] == nil {
				jsonObj["id"] = UUID().uuidString
			}
			let bodyWithId = try JSONSerialization.data(withJSONObject: jsonObj)
			let config = try JSONDecoder().decode(PeripheryConfiguration.self, from: bodyWithId)
			await MainActor.run { server.configManager.addConfiguration(config) }
			return encodeConfig(config, status: 201)
		} catch {
			return .error("invalid configuration JSON: \(error.localizedDescription)", status: 400)
		}
	}

	private static func encodeConfig(_ config: PeripheryConfiguration, status: Int = 200) -> Router.Response {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		let data = try? encoder.encode(config)
		return Router.Response(statusCode: status, body: data, contentType: "application/json")
	}

	private static func encodeConfigs(_ configs: [PeripheryConfiguration]) -> Router.Response {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		let data = try? encoder.encode(configs)
		return Router.Response(statusCode: 200, body: data, contentType: "application/json")
	}
}
