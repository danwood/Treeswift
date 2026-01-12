//
//  LaunchArgumentsHandler.swift
//  Treeswift
//
//  Handles parsing of command-line launch arguments to determine if app runs in GUI or CLI mode
//

import Foundation

enum LaunchMode: Sendable {
	case gui
	case list
	case scan(configurationName: String)
}

@MainActor
final class LaunchArgumentsHandler {
	/**
	 Parses command-line arguments to determine launch mode

	 Recognizes:
	 - No arguments or non-flag arguments: GUI mode
	 - --list: List all configurations and exit
	 - --scan <name>: Run scan for named configuration and exit

	 Exits with code 1 for invalid arguments
	 */
	static func parseLaunchMode() -> LaunchMode {
		let arguments = ProcessInfo.processInfo.arguments

		// Skip first argument (executable path)
		guard arguments.count > 1 else { return .gui }

		let firstArg = arguments[1]

		if firstArg == "--list" {
			return .list
		}

		if firstArg == "--scan" {
			guard arguments.count > 2 else {
				fputs("Error: --scan requires a configuration name\n", stderr)
				fputs("Usage: Treeswift --scan <configuration_name>\n", stderr)
				exit(1)
			}
			return .scan(configurationName: arguments[2])
		}

		// Unknown argument - print usage and exit
		if firstArg.hasPrefix("-") {
			fputs("Unknown argument: \(firstArg)\n", stderr)
			fputs("Usage:\n", stderr)
			fputs("  Treeswift              # Launch GUI\n", stderr)
			fputs("  Treeswift --list       # List all configurations\n", stderr)
			fputs("  Treeswift --scan <name> # Run scan for configuration\n", stderr)
			exit(1)
		}

		return .gui
	}
}
