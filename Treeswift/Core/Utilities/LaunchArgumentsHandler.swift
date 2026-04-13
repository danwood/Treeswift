//
//  LaunchArgumentsHandler.swift
//  Treeswift
//
//  Handles parsing of command-line launch arguments to determine if app runs in GUI or CLI mode
//

import Foundation

enum LaunchMode: Sendable {
	case gui(scanConfiguration: String? = nil, automationPort: UInt16? = nil, noCache: Bool = false)
	case list
}

final class LaunchArgumentsHandler {
	/**
	 Parses command-line arguments to determine launch mode.

	 Recognizes:
	 - No arguments or non-flag arguments: GUI mode
	 - --list: List all configurations and exit (CLI mode)
	 - --scan <name>: Launch GUI and start scan for named configuration
	 - --automation-port <port>: Launch GUI with embedded HTTP automation server on the given port

	 --scan and --automation-port may be combined in any order.
	 Exits with code 1 for invalid arguments.
	 */
	nonisolated static func parseLaunchMode() -> LaunchMode {
		let arguments = ProcessInfo.processInfo.arguments

		// Skip first argument (executable path)
		guard arguments.count > 1 else { return .gui(scanConfiguration: nil, automationPort: nil) }

		// Check for --list first (CLI-only mode, no other args apply)
		if arguments.contains("--list") {
			return .list
		}

		var scanConfiguration: String? = nil
		var automationPort: UInt16? = nil
		var noCache = false
		var i = 1
		while i < arguments.count {
			let arg = arguments[i]
			switch arg {
			case "--scan":
				i += 1
				guard i < arguments.count else {
					fputs("Error: --scan requires a configuration name\n", stderr)
					fputs("Usage: Treeswift --scan <configuration_name>\n", stderr)
					exit(1)
				}
				scanConfiguration = arguments[i]
			case "--automation-port":
				i += 1
				guard i < arguments.count else {
					fputs("Error: --automation-port requires a port number\n", stderr)
					fputs("Usage: Treeswift --automation-port <port>\n", stderr)
					exit(1)
				}
				guard let port = UInt16(arguments[i]) else {
					fputs("Error: --automation-port value '\(arguments[i])' is not a valid port number\n", stderr)
					exit(1)
				}
				automationPort = port
			case "--no-cache":
				noCache = true
			default:
				if arg.hasPrefix("-") {
					fputs("Unknown argument: \(arg)\n", stderr)
					fputs("Usage:\n", stderr)
					fputs("  Treeswift                                    # Launch GUI\n", stderr)
					fputs("  Treeswift --list                             # List all configurations\n", stderr)
					fputs("  Treeswift --scan <name>                      # Launch GUI and run scan\n", stderr)
					fputs(
						"  Treeswift --automation-port <port>           # Launch GUI with HTTP automation server\n",
						stderr
					)
					fputs(
						"  Treeswift --no-cache                         # Launch GUI without restoring cached results\n",
						stderr
					)
					exit(1)
				}
			}
			i += 1
		}

		return .gui(scanConfiguration: scanConfiguration, automationPort: automationPort, noCache: noCache)
	}
}
