//
//  OptionKeyMonitor.swift
//  Treeswift
//
//  Monitor Option key state for SwiftUI views
//

// periphery:ignore:all
import SwiftUI
import AppKit

/**
 A view modifier that monitors the Option key state and updates a binding.

 This modifier listens to flag change events from NSEvent and updates
 the provided binding whenever the Option key is pressed or released.
 */
struct OptionKeyMonitorModifier: ViewModifier {
	@Binding var isOptionKeyPressed: Bool

	func body(content: Content) -> some View {
		content
			.onAppear {
				NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
					isOptionKeyPressed = event.modifierFlags.contains(.option)
					return event
				}
			}
			.onDisappear {
				isOptionKeyPressed = false
			}
	}
}

extension View {
	/**
	 Monitors the Option key state and updates the provided binding.
	 */
	func monitorOptionKey(_ isPressed: Binding<Bool>) -> some View {
		modifier(OptionKeyMonitorModifier(isOptionKeyPressed: isPressed))
	}
}
