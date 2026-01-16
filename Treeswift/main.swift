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

	// Only handle true CLI-only modes (--list)
	// GUI modes (including --scan) are handled by TreeswiftApp
	if case .list = mode {
		let runner = CLIScanRunner()
		runner.listConfigurations()
		exit(0)
	}
}

// Parse launch mode to determine how to proceed
let launchMode = LaunchArgumentsHandler.parseLaunchMode()

switch launchMode {
case .list:
	// CLI-only mode - run and exit
	Task { @MainActor in
		await runCLIMode()
		// If we get here, something went wrong
		exit(1)
	}
	// Keep running until exit() is called
	RunLoop.main.run()

case .gui:
	// GUI mode (with or without --scan parameter) - launch SwiftUI app
	TreeswiftApp.main()
}
