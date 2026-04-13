//
//	TreeswiftApp.swift
//	Treeswift
//
//	Created by Dan Wood on 10/1/25.
//

import AppKit
import SwiftUI

// Application delegate used solely to hook app lifecycle events that SwiftUI doesn't expose cleanly.
final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
	var automationServer: AutomationServer?

	func applicationWillTerminate(_ notification: Notification) {
		automationServer?.stop()
	}
}

struct TreeswiftApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	@State private var configManager = ConfigurationManager()
	@State private var scanStateManager = ScanStateManager(noCache: noCache)
	@State private var filterState = FilterState()
	@State private var inspectorState = FileInspectorState()
	@State private var automationActivity = AutomationActivityState()
	@Environment(\.scenePhase) private var scenePhase

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(configManager)
				.environment(scanStateManager)
				.environment(filterState)
				.environment(inspectorState)
				.environment(automationActivity)
				.onAppear {
					scanStateManager.restoreAllCaches(for: configManager.configurations)
					startAutomationServerIfNeeded()
					appDelegate.automationServer?.markReady()
				}
		}
		.onChange(of: scenePhase) { oldPhase, newPhase in
			// Check for file changes when app returns to foreground
			if oldPhase != .active, newPhase == .active {
				inspectorState.checkCurrentFile()
			}
		}
		.defaultSize(width: LayoutConstants.windowDefaultWidth, height: LayoutConstants.windowDefaultHeight)
		.windowToolbarStyle(.unifiedCompact)
		.windowStyle(.hiddenTitleBar)
		.commands {
			// Use standard text editing commands, but customize Copy to handle both text and custom tree row data
			TextEditingCommands()
			FindCommand()
			CommandGroup(replacing: .pasteboard) {
				Button("Cut") {
					NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
				}
				.keyboardShortcut("x", modifiers: .command)

				CopyCommand()

				Button("Paste") {
					NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
				}
				.keyboardShortcut("v", modifiers: .command)

				Button("Select All") {
					NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
				}
				.keyboardShortcut("a", modifiers: .command)

				Divider()

				Button("Delete") {
					NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: nil)
				}
			}
		}
	}

	private func startAutomationServerIfNeeded() {
		guard appDelegate.automationServer == nil, let port = automationPort else { return }
		let server = AutomationServer(
			port: port,
			configManager: configManager,
			scanStateManager: scanStateManager,
			filterState: filterState,
			activityState: automationActivity
		)
		appDelegate.automationServer = server
		Task {
			await server.start()
		}
	}
}

/* folderprivate */
struct CopyCommand: View {
	@FocusedValue(\.copyMenuTitle) var copyMenuTitle: String?

	var body: some View {
		Button(copyMenuTitle ?? "Copy") {
			// Send native copy action to the responder chain.
			// This works for both:
			// - Native text selection in Text views (.textSelection(.enabled))
			// - Custom copyableText focused values from tree rows
			// The system will handle the copy if there's something selected,
			// or do nothing if there isn't - no need to disable the button.
			NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
		}
		.keyboardShortcut("c", modifiers: .command)
	}
}

/* folderprivate */
struct FindCommand: Commands {
	@FocusedValue(\.activateSearch) var activateSearch

	var body: some Commands {
		CommandGroup(after: .textEditing) {
			Button("Find\u{2026}") {
				activateSearch?()
			}
			.keyboardShortcut("f", modifiers: .command)
		}
	}
}
