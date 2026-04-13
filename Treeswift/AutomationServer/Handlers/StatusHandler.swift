//
//  StatusHandler.swift
//  Treeswift
//

import Foundation

private nonisolated struct StatusResponse: Codable, Sendable {
	let state: String
	let version: String
}

private nonisolated struct ReadyResponse: Codable, Sendable {
	let ready: Bool
	let pid: Int32
}

enum StatusHandler {
	static func handleStatus(server: AutomationServer) async -> Router.Response {
		let isScanning = await MainActor.run {
			server.scanStateManager.isAnyScanning
		}
		let state = isScanning ? "scanning" : "idle"
		return .json(StatusResponse(state: state, version: "1.0"))
	}

	/**
	 Returns 200 when the server is fully initialized (configs loaded, caches restored).
	 Returns 503 while still starting up. Scripts should poll this before starting a scan.
	 */
	static func handleReady(server: AutomationServer) async -> Router.Response {
		let isReady = await MainActor.run { server.isReady }
		let pid = ProcessInfo.processInfo.processIdentifier
		if isReady {
			return .json(ReadyResponse(ready: true, pid: pid))
		} else {
			return .json(ReadyResponse(ready: false, pid: pid), status: 503)
		}
	}
}
