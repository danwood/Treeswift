//
//  LaunchArgumentsHandler.swift
//  Treeswift
//
//  Handles parsing of command-line launch arguments to determine if app runs in GUI or CLI mode
//

import Foundation

enum LaunchMode: Sendable {
	case gui(scanConfiguration: String? = nil)
	case list
}

final class LaunchArgumentsHandler {
	/**
	 Parses command-line arguments to determine launch mode

	 Recognizes:
	 - No arguments or non-flag arguments: GUI mode
	 - --list: List all configurations and exit (CLI mode)
	 - --scan <name>: Launch GUI and start scan for named configuration

	 Exits with code 1 for invalid arguments
	 */
	nonisolated static func parseLaunchMode() -> LaunchMode {
		let arguments = ProcessInfo.processInfo.arguments

		// Skip first argument (executable path)
		guard arguments.count > 1 else { return .gui(scanConfiguration: nil) }

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
			return .gui(scanConfiguration: arguments[2])
		}

		// Unknown argument - print usage and exit
		if firstArg.hasPrefix("-") {
			fputs("Unknown argument: \(firstArg)\n", stderr)
			fputs("Usage:\n", stderr)
			fputs("  Treeswift              # Launch GUI\n", stderr)
			fputs("  Treeswift --list       # List all configurations\n", stderr)
			fputs("  Treeswift --scan <name> # Launch GUI and run scan for configuration\n", stderr)
			exit(1)
		}

		return .gui(scanConfiguration: nil)
	}
}
