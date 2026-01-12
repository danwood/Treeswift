//
//  main.swift
//  Treeswift
//
//  Custom main entry point to handle CLI mode before SwiftUI initialization
//

import Foundation
import SwiftUI

@MainActor
func runCLIMode() async {
	let mode = LaunchArgumentsHandler.parseLaunchMode()

	guard case .gui = mode else {
		let runner = CLIScanRunner()

		do {
			switch mode {
			case .list:
				runner.listConfigurations()
				exit(0)

			case .scan(let configName):
				try await runner.runScan(configurationName: configName)
				exit(0)

			case .gui:
				break
			}
		} catch {
			fputs("\(error)\n", stderr)
			exit(1)
		}
		return
	}
}

// Check if CLI mode and handle before launching GUI
let mode = ProcessInfo.processInfo.arguments.count > 1 && ProcessInfo.processInfo.arguments[1].hasPrefix("--")

if mode {
	// CLI mode - run async task and wait
	Task { @MainActor in
		await runCLIMode()
		// If we get here, something went wrong
		exit(1)
	}
	// Keep running until exit() is called
	RunLoop.main.run()
} else {
	// GUI mode - launch SwiftUI app normally
	TreeswiftApp.main()
}
