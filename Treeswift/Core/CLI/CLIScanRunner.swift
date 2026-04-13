//
//  CLIScanRunner.swift
//  Treeswift
//
//  Executes CLI operations (list configurations, run scans) in headless mode
//

import AppKit
import Foundation

@MainActor
final class CLIScanRunner {
	private let configManager = ConfigurationManager()

	/**
	 Lists all saved configurations to stdout

	 Prints one configuration name per line. Only shows configurations with valid project paths,
	 using the same display names as the GUI (derived from project path).
	 */
	func listConfigurations() {
		for config in configManager.configurations {
			// Skip configurations without a project path (incomplete/new configurations)
			guard let projectPath = config.project else { continue }

			// Use the same display name logic as the GUI
			let displayName = projectNameForConfig(config, projectPath: projectPath)
			print(displayName)
		}
	}

	/**
	 Derives the display name for a configuration from its project path.

	 Matches the logic in SidebarView.projectNameForConfig().
	 */
	private func projectNameForConfig(_ config: PeripheryConfiguration, projectPath: String) -> String {
		let url = URL(fileURLWithPath: projectPath)

		switch config.projectType {
		case .xcode:
			// For Xcode projects, show project name without extension
			return url.deletingPathExtension().lastPathComponent
		case .swiftPackage:
			// For SPM projects, show folder name (not "Package.swift")
			return url.deletingLastPathComponent().lastPathComponent
		}
	}

	/**
	 Executes a scan for the specified configuration and waits for completion

	 Outputs progress to stderr and results to console (if configuration's shouldLogToConsole is enabled)
	 Throws CLIScanError if configuration not found or scan fails
	 */
	// MARK: - Private Helpers
}
