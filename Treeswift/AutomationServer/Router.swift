//
//  Router.swift
//  Treeswift
//
//  Routes incoming HTTP requests to the appropriate handler.
//  Pure value type (struct) — Sendable by default. All @MainActor state
//  access is dispatched internally via await MainActor.run { }.
//

import AppKit
import Foundation

private nonisolated struct RouterErrorBody: Codable, Sendable { let error: String }
private nonisolated struct RouterOkBody: Codable, Sendable { let ok: Bool }

struct Router: Sendable {
	struct Request: Sendable {
		let method: String
		let path: String
		let pathComponents: [String]
		let queryItems: [String: String]
		let body: Data?
	}

	struct Response: Sendable {
		let statusCode: Int
		let body: Data?
		let contentType: String?

		static func json(_ encodable: some Encodable & Sendable, status: Int = 200) -> Response {
			let encoder = JSONEncoder()
			encoder.outputFormatting = .sortedKeys
			let data = try? encoder.encode(encodable)
			return Response(statusCode: status, body: data, contentType: "application/json")
		}

		static func error(_ message: String, status: Int) -> Response {
			json(RouterErrorBody(error: message), status: status)
		}

		static func text(_ string: String, status: Int = 200) -> Response {
			Response(statusCode: status, body: Data(string.utf8), contentType: "text/plain; charset=utf-8")
		}
	}

	private let server: AutomationServer

	init(server: AutomationServer) {
		self.server = server
	}

	/**
	 Returns a short human-readable label for a request, used in the activity banner.
	 */
	private func activityLabel(for request: Request) -> String {
		let c = request.pathComponents
		let m = request.method
		if m == "GET", c == ["status"] { return "GET /status" }
		if m == "GET", c == ["ready"] { return "GET /ready" }
		if m == "GET", c == ["configurations"] { return "GET /configurations" }
		if m == "POST", c == ["configurations"] { return "POST /configurations" }
		if m == "POST", c == ["quit"] { return "POST /quit" }
		if c.count >= 3, c[0] == "configurations" {
			let id = c[1]
			let tail = c.dropFirst(2).joined(separator: "/")
			return "\(m) \(id)/\(tail)"
		}
		return "\(m) \(c.joined(separator: "/"))"
	}

	func handle(request: Request) async -> Response {
		let label = activityLabel(for: request)
		await MainActor.run { server.activityState.activeCommand = label }
		defer {
			Task { @MainActor in server.activityState.activeCommand = nil }
		}

		let c = request.pathComponents
		let method = request.method

		if method == "GET", c == ["status"] {
			return await StatusHandler.handleStatus(server: server)
		}

		if method == "GET", c == ["ready"] {
			return await StatusHandler.handleReady(server: server)
		}

		if method == "GET", c == ["configurations"] {
			return await ConfigurationsHandler.handleList(server: server)
		}

		if method == "POST", c == ["configurations"] {
			return await ConfigurationsHandler.handleCreate(server: server, request: request)
		}

		if method == "GET", c.count == 2, c[0] == "configurations" {
			return await ConfigurationsHandler.handleGet(server: server, id: c[1])
		}

		if c.count >= 3, c[0] == "configurations" {
			let id = c[1]

			if method == "POST", c.count == 3, c[2] == "scan" {
				return await ScanHandler.handleStart(server: server, id: id)
			}
			if method == "GET", c.count == 4, c[2] == "scan", c[3] == "status" {
				return await ScanHandler.handleStatus(server: server, id: id)
			}
			if method == "GET", c.count == 4, c[2] == "scan", c[3] == "wait" {
				return await ScanHandler.handleWait(server: server, id: id)
			}
			if method == "GET", c.count == 5, c[2] == "scan", c[3] == "log", c[4] == "raw" {
				return await ScanHandler.handleLog(server: server, id: id)
			}

			if method == "GET", c.count == 4, c[2] == "results", c[3] == "periphery-tree" {
				return await ResultsHandler.handlePeripheryTree(server: server, id: id)
			}
			if method == "GET", c.count == 5, c[2] == "results", c[3] == "categories" {
				return await ResultsHandler.handleCategory(server: server, id: id, name: c[4])
			}
			if method == "GET", c.count == 4, c[2] == "results", c[3] == "files-tree" {
				return await ResultsHandler.handleFilesTree(server: server, id: id)
			}
			if method == "GET", c.count == 4, c[2] == "results", c[3] == "summary" {
				return await ResultsHandler.handleSummary(server: server, id: id)
			}
			if method == "GET", c.count == 4, c[2] == "results", c[3] == "raw" {
				let filePath = request.queryItems["file"] ?? ""
				return await ResultsHandler.handleRawResults(server: server, id: id, filePath: filePath)
			}

			if method == "POST", c.count == 4, c[2] == "removal", c[3] == "preview" {
				return await RemovalHandler.handlePreview(server: server, id: id, request: request)
			}
			if method == "POST", c.count == 4, c[2] == "removal", c[3] == "execute" {
				return await RemovalHandler.handleExecute(server: server, id: id, request: request)
			}
			if method == "GET", c.count == 5, c[2] == "removal", c[3] == "log", c[4] == "raw" {
				return await RemovalHandler.handleLog(server: server, id: id)
			}

			if method == "GET", c.count == 3, c[2] == "view-options" {
				return await ViewOptionsHandler.handleGet(server: server, id: id)
			}
			if method == "POST", c.count == 3, c[2] == "view-options" {
				return await ViewOptionsHandler.handleSet(server: server, id: id, request: request)
			}
		}

		if method == "POST", c == ["quit"] {
			await MainActor.run { NSApp.terminate(nil) }
			return .json(RouterOkBody(ok: true))
		}

		return .error("not found", status: 404)
	}
}

/**
 Looks up a configuration and its scan state by UUID string or name.
 Tries UUID parsing first; falls back to case-insensitive name match.
 Returns nil if no matching configuration exists.
 */
@MainActor
func resolveConfig(server: AutomationServer, id: String) -> (PeripheryConfiguration, ScanState)? {
	let config: PeripheryConfiguration?
	if let uuid = UUID(uuidString: id) {
		config = server.configManager.configurations.first { $0.id == uuid }
	} else {
		let lower = id.lowercased()
		config = server.configManager.configurations.first { $0.name.lowercased() == lower }
	}
	guard let config else { return nil }
	let state = server.scanStateManager.getState(for: config.id)
	return (config, state)
}
