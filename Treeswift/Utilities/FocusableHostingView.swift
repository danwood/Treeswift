//
//  FocusableHostingView.swift
//  Treeswift
//
//  Invisible NSView background for tree keyboard navigation using AppKit first responder
//

import SwiftUI
import AppKit

/// Invisible NSView that can become first responder and handle keyboard events
class FocusableNSView: NSView {
	var onArrowKey: ((KeyboardKey) -> Void)?

	enum KeyboardKey {
		case up, down
	}

	override var acceptsFirstResponder: Bool { true }

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		// Claim first responder on any click
		window?.makeFirstResponder(self)
	}

	override func keyDown(with event: NSEvent) {
		// Handle arrow keys
		switch event.keyCode {
		case 126: // Up arrow
			onArrowKey?(.up)
		case 125: // Down arrow
			onArrowKey?(.down)
		default:
			super.keyDown(with: event)
		}
	}
}

/// Invisible NSView that claims focus and handles keyboard events, placed as background
struct FocusClaimingView: NSViewRepresentable {
	@Binding var selectedID: String?
	let visibleItems: [String]
	var claimFocusTrigger: Binding<Bool>? = nil

	func makeNSView(context: Context) -> FocusableNSView {
		let view = FocusableNSView()
		view.onArrowKey = context.coordinator.handleArrowKey
		return view
	}

	func updateNSView(_ nsView: FocusableNSView, context: Context) {
		let previousSelection = context.coordinator.selectedID.wrappedValue
		let previousTrigger = context.coordinator.claimFocusTrigger?.wrappedValue ?? false

		context.coordinator.updateBindings(
			selectedID: $selectedID,
			visibleItems: visibleItems,
			claimFocusTrigger: claimFocusTrigger
		)

		// Existing: claim on selection change
		if previousSelection != selectedID {
			nsView.window?.makeFirstResponder(nsView)
		}

		// New: claim on trigger change to true
		if let trigger = claimFocusTrigger?.wrappedValue, trigger != previousTrigger, trigger {
			nsView.window?.makeFirstResponder(nsView)
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(selectedID: $selectedID, visibleItems: visibleItems, claimFocusTrigger: claimFocusTrigger)
	}

	class Coordinator {
		var selectedID: Binding<String?>
		var visibleItems: [String]
		var claimFocusTrigger: Binding<Bool>?

		init(selectedID: Binding<String?>, visibleItems: [String], claimFocusTrigger: Binding<Bool>?) {
			self.selectedID = selectedID
			self.visibleItems = visibleItems
			self.claimFocusTrigger = claimFocusTrigger
		}

		func updateBindings(
			selectedID: Binding<String?>,
			visibleItems: [String],
			claimFocusTrigger: Binding<Bool>?
		) {
			self.selectedID = selectedID
			self.visibleItems = visibleItems
			self.claimFocusTrigger = claimFocusTrigger
		}

		func handleArrowKey(_ key: FocusableNSView.KeyboardKey) {
			switch key {
			case .up:
				selectedID.wrappedValue = TreeKeyboardNavigation.moveSelectionUp(
					currentSelection: selectedID.wrappedValue,
					visibleItems: visibleItems
				)
			case .down:
				selectedID.wrappedValue = TreeKeyboardNavigation.moveSelectionDown(
					currentSelection: selectedID.wrappedValue,
					visibleItems: visibleItems
				)
			}
		}
	}
}
