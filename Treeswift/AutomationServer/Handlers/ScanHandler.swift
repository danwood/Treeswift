//
//  ScanHandler.swift
//  Treeswift
//

import Foundation

private nonisolated struct ScanStatusResponse: Codable, Sendable {
	let isScanning: Bool
	let scanStatus: String
	let errorMessage: String?
}

private nonisolated struct ScanOkResponse: Codable, Sendable {
	let ok: Bool
}

enum ScanHandler {
	static func handleStart(server: AutomationServer, id: String) async -> Router.Response {
		guard let (config, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let alreadyScanning = await MainActor.run { state.isScanning }
		if alreadyScanning {
			return .error("scan already running", status: 409)
		}

		await MainActor.run { state.startScan(configuration: config) }
		return .json(ScanOkResponse(ok: true))
	}

	static func handleStatus(server: AutomationServer, id: String) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let response = await MainActor.run {
			ScanStatusResponse(
				isScanning: state.isScanning,
				scanStatus: state.scanStatus,
				errorMessage: state.errorMessage
			)
		}
		return .json(response)
	}

	static func handleWait(server: AutomationServer, id: String) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		// Register this wait as a tracked Task so stop() can cancel it
		let watcherTask = Task<Void, Never> {
			while !Task.isCancelled {
				let isScanning = await MainActor.run { state.isScanning }
				if !isScanning { break }
				try? await Task.sleep(for: .milliseconds(200))
			}
		}
		let token = await MainActor.run { server.addWatcherTask(watcherTask) }
		defer {
			Task { await MainActor.run { server.removeWatcherTask(token: token) } }
		}

		do {
			try await withTaskCancellationHandler {
				await watcherTask.value
			} onCancel: {
				watcherTask.cancel()
			}
		} catch is CancellationError {
			return .error("wait cancelled", status: 499)
		}

		let response = await MainActor.run {
			ScanStatusResponse(
				isScanning: state.isScanning,
				scanStatus: state.scanStatus,
				errorMessage: state.errorMessage
			)
		}
		return .json(response)
	}

	static func handleLog(server: AutomationServer, id: String) async -> Router.Response {
		guard let (_, state) = await MainActor.run(resultType: (PeripheryConfiguration, ScanState)?.self, body: {
			resolveConfig(server: server, id: id)
		}) else {
			return .error("configuration not found", status: 404)
		}

		let logLines = await MainActor.run { state.scanLogBuffer }
		if logLines.isEmpty {
			return .error("no scan log available", status: 404)
		}
		return .text(logLines.joined(separator: "\n"))
	}
}
