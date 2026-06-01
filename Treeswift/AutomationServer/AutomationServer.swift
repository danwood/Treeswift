//
//  AutomationServer.swift
//  Treeswift
//
//  Embedded HTTP automation server for external control of Treeswift.
//  Listens on localhost only. Started when --automation-port <port> is passed at launch.
//

import Foundation
import Network

@MainActor
final class AutomationServer {
	private let port: UInt16
	let configManager: ConfigurationManager
	let scanStateManager: ScanStateManager
	let filterState: FilterState
	let activityState: AutomationActivityState
	private var listener: NWListener?
	private var watcherTasks: [UUID: Task<Void, Never>] = [:]
	private let statusFilePath = "/tmp/treeswift-control.json"
	private let errorFilePath = "/tmp/treeswift-control.error"
	private let serverQueue = DispatchQueue(label: "com.treeswift.automation", qos: .utility)
	private(set) var isReady = false
	private var startContinuation: UnsafeContinuation<Void, Never>?

	init(
		port: UInt16,
		configManager: ConfigurationManager,
		scanStateManager: ScanStateManager,
		filterState: FilterState,
		activityState: AutomationActivityState
	) {
		self.port = port
		self.configManager = configManager
		self.scanStateManager = scanStateManager
		self.filterState = filterState
		self.activityState = activityState
	}

	/**
	 Starts the HTTP server. Exits the process with code 1 if the port is already in use.
	 Writes /tmp/treeswift-control.json when ready; /tmp/treeswift-control.error on failure.
	 */
	func start() async {
		checkStaleStatusFile()
		let router = Router(server: self)

		guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
			let msg = "Invalid automation port: \(port)"
			fputs("Error: \(msg)\n", stderr)
			writeErrorFile(msg)
			exit(1)
		}

		let params = NWParameters.tcp
		let statusFilePath = statusFilePath
		let errorFilePath = errorFilePath
		let serverPort = port

		guard let newListener = try? NWListener(using: params, on: endpointPort) else {
			let msg = "Failed to create listener on port \(port)"
			fputs("Error: \(msg)\n", stderr)
			writeErrorFile(msg)
			exit(1)
		}
		listener = newListener

		// Capture router as a local value — it's a Sendable struct
		let capturedRouter = router

		newListener.stateUpdateHandler = { state in
			switch state {
			case .ready:
				let pid = ProcessInfo.processInfo.processIdentifier
				let now = ISO8601DateFormatter().string(from: Date())
				let json = "{\"port\":\(serverPort),\"pid\":\(pid),\"startedAt\":\"\(now)\"}"
				do {
					try json.write(toFile: statusFilePath, atomically: true, encoding: .utf8)
					fputs("Automation server ready on port \(serverPort)\n", stderr)
				} catch {
					fputs("Warning: Could not write status file: \(error)\n", stderr)
				}
			case let .failed(error):
				let msg = "Automation server failed to start: \(error). Is port \(serverPort) already in use?"
				fputs("Error: \(msg)\n", stderr)
				try? msg.write(toFile: errorFilePath, atomically: true, encoding: .utf8)
				exit(1)
			case let .waiting(error):
				let msg = "Automation server cannot bind to port \(serverPort): \(error)"
				fputs("Error: \(msg)\n", stderr)
				try? msg.write(toFile: errorFilePath, atomically: true, encoding: .utf8)
				exit(1)
			default:
				break
			}
		}

		newListener.newConnectionHandler = { connection in
			let conn = HTTPConnection(connection: connection, router: capturedRouter)
			conn.start(on: DispatchQueue(label: "com.treeswift.automation.conn", qos: .utility))
		}

		newListener.start(queue: serverQueue)

		// Keep the async context alive until stop() is called or the Task is cancelled.
		await withTaskCancellationHandler {
			await withUnsafeContinuation { continuation in
				startContinuation = continuation
			}
		} onCancel: {
			Task { @MainActor [weak self] in
				self?.resumeStartContinuation()
			}
		}
	}

	@MainActor
	private func resumeStartContinuation() {
		startContinuation?.resume()
		startContinuation = nil
	}

	/**
	 Marks the server as fully initialized (configs loaded, caches restored).
	 Called by TreeswiftApp after restoreAllCaches completes.
	 */
	func markReady() {
		isReady = true
	}

	/** Writes an error message to the error file so scripts can detect startup failure. */
	private nonisolated func writeErrorFile(_ message: String) {
		try? message.write(toFile: errorFilePath, atomically: true, encoding: .utf8)
	}

	/**
	 Checks if a stale status file exists from a previous run.
	 If the stored port matches and the port is in use, exits (another instance is running).
	 Otherwise removes stale files and proceeds.
	 */
	private func checkStaleStatusFile() {
		try? FileManager.default.removeItem(atPath: errorFilePath)

		guard let data = try? Data(contentsOf: URL(fileURLWithPath: statusFilePath)),
		      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let storedPort = json["port"] as? Int,
		      UInt16(storedPort) == port
		else {
			try? FileManager.default.removeItem(atPath: statusFilePath)
			return
		}

		let isRunning = checkPortInUse(port: port)
		if isRunning {
			fputs("Error: Another Treeswift automation server is already running on port \(port)\n", stderr)
			exit(1)
		} else {
			fputs("Note: Removing stale status file from previous run\n", stderr)
			try? FileManager.default.removeItem(atPath: statusFilePath)
		}
	}

	private nonisolated func checkPortInUse(port: UInt16) -> Bool {
		// Attempt a synchronous TCP connection to detect if port is in use.
		// Times out after 1 second to avoid blocking startup.
		// Box the result so it can be safely captured by the state-update closure;
		// the semaphore ensures the closure's write happens-before the read below.
		final class ResultBox: @unchecked Sendable {
			var value = false
		}
		let resultBox = ResultBox()
		let semaphore = DispatchSemaphore(value: 0)
		let connection = NWConnection(
			host: "127.0.0.1",
			port: NWEndpoint.Port(rawValue: port) ?? 80,
			using: .tcp
		)
		connection.stateUpdateHandler = { state in
			switch state {
			case .ready:
				resultBox.value = true
				connection.cancel()
				semaphore.signal()
			case .failed, .cancelled:
				semaphore.signal()
			default:
				break
			}
		}
		connection.start(queue: DispatchQueue(label: "com.treeswift.portcheck", qos: .userInitiated))
		let timedOut = semaphore.wait(timeout: .now() + 1.0) == .timedOut
		if timedOut {
			connection.cancel()
		}
		return resultBox.value
	}

	/**
	 Registers a long-poll watcher task so it can be cancelled on server stop.
	 Returns a token that must be passed to removeWatcherTask when done.
	 */
	func addWatcherTask(_ task: Task<Void, Never>) -> UUID {
		let token = UUID()
		watcherTasks[token] = task
		return token
	}

	func removeWatcherTask(token: UUID) {
		watcherTasks.removeValue(forKey: token)
	}

	/**
	 Stops the server and cleans up status files.
	 Cancels all active long-poll watcher tasks.
	 */
	func stop() {
		for (_, task) in watcherTasks {
			task.cancel()
		}
		watcherTasks.removeAll()
		listener?.cancel()
		listener = nil
		resumeStartContinuation()
		try? FileManager.default.removeItem(atPath: statusFilePath)
		try? FileManager.default.removeItem(atPath: errorFilePath)
		fputs("Automation server stopped\n", stderr)
	}
}
