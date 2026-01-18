//
//  PrintCapture.swift
//  Treeswift
//
//  Utility to capture stdout print statements
//

import Foundation

// periphery:ignore
final class PrintCapture {
	private let originalStdout: Int32
	private let pipe: Pipe
	private nonisolated(unsafe) var capturedOutput: String = ""

	// Global lock to prevent concurrent stdout redirection
	// Multiple concurrent PrintCapture operations would interfere with each other
	private nonisolated static let captureLock = NSLock()

	nonisolated init() {
		pipe = Pipe()
		originalStdout = dup(STDOUT_FILENO)
	}

	nonisolated func startCapturing() {
		capturedOutput = ""
		dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
	}

	nonisolated func stopCapturing() -> String {
		fflush(stdout)
		dup2(originalStdout, STDOUT_FILENO)

		// Close the write end to signal EOF
		try? pipe.fileHandleForWriting.close()

		// Read all available data
		let allData = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()

		if let output = String(data: allData, encoding: .utf8) {
			capturedOutput = output
		}

		return capturedOutput
	}

	deinit {
		close(originalStdout)
	}

	/// Captures stdout from the given block
	/// Thread-safe: Uses a lock to prevent concurrent stdout redirection
	nonisolated static func capture(_ block: () -> Void) -> String {
		captureLock.lock()
		defer { captureLock.unlock() }

		let capture = PrintCapture()
		capture.startCapturing()
		block()
		return capture.stopCapturing()
	}
}
