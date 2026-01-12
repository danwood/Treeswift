//
//  CLIScanRunner.swift
//  Treeswift
//
//  Executes CLI operations (list configurations, run scans) in headless mode
//

import Foundation
import AppKit

@MainActor
final class CLIScanRunner {
	private let configManager = ConfigurationManager()
	private let scanStateManager = ScanStateManager()

	/**
	 Lists all saved configurations to stdout

	 Prints one configuration name per line
	 */
	func listConfigurations() {
		for config in configManager.configurations {
			print(config.name)
		}
	}

	/**
	 Executes a scan for the specified configuration and waits for completion

	 Outputs progress to stderr and results to console (if configuration's shouldLogToConsole is enabled)
	 Throws CLIScanError if configuration not found or scan fails
	 */
	func runScan(configurationName: String) async throws {
		// Find configuration by name
		guard let config = findConfiguration(named: configurationName) else {
			throw CLIScanError.configurationNotFound(configurationName)
		}

		fputs("Starting scan for configuration: \(configurationName)\n", stderr)

		// Get or create scan state
		let scanState = scanStateManager.getState(for: config.id)

		// Start the scan
		scanState.startScan(configuration: config)

		// Monitor scan progress
		try await waitForScanCompletion(scanState: scanState)

		// Check for errors
		if let errorMessage = scanState.errorMessage {
			throw CLIScanError.scanFailed(errorMessage)
		}

		// Output results summary
		outputResultsSummary(scanState: scanState, configuration: config)
	}

	// MARK: - Private Helpers

	private func findConfiguration(named name: String) -> PeripheryConfiguration? {
		configManager.configurations.first(where: { $0.name == name })
	}

	private func waitForScanCompletion(scanState: ScanState) async throws {
		// Poll isScanning until it becomes false
		while scanState.isScanning {
			// Check for cancellation
			try Task.checkCancellation()

			// Sleep briefly to avoid busy-waiting
			try await Task.sleep(for: .milliseconds(100))
		}
	}

	private func outputResultsSummary(scanState: ScanState, configuration: PeripheryConfiguration) {
		let resultCount = scanState.scanResults.count

		fputs("\n", stderr)
		fputs("Scan complete for '\(configuration.name)'\n", stderr)
		fputs("Found \(resultCount) issue\(resultCount == 1 ? "" : "s")\n", stderr)

		if resultCount > 0 {
			fputs("\nResults logged above\n", stderr)
		}
	}
}

enum CLIScanError: Error, CustomStringConvertible {
	case configurationNotFound(String)
	case scanFailed(String)

	var description: String {
		switch self {
		case .configurationNotFound(let name):
			"Configuration not found: '\(name)'\nUse --list to see available configurations"
		case .scanFailed(let message):
			"Scan failed: \(message)"
		}
	}
}
