//
//	TreeswiftApp.swift
//	Treeswift
//
//	Created by Dan Wood on 10/1/25.
//

import SwiftUI

struct TreeswiftApp: App {
	@State private var inspectorState = FileInspectorState()
	@Environment(\.scenePhase) private var scenePhase

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(inspectorState)
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
}

private struct CopyCommand: View {
	@FocusedValue(\.copyMenuTitle) private var copyMenuTitle: String?

	var body: some View {
		Button(copyMenuTitle ?? "Copy") {
			/* Send native copy action to the responder chain.
			 This works for both:
			 - Native text selection in Text views (.textSelection(.enabled))
			 - Custom copyableText focused values from tree rows
			 The system will handle the copy if there's something selected,
			 or do nothing if there isn't - no need to disable the button. */
			NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
		}
		.keyboardShortcut("c", modifiers: .command)
	}
}
