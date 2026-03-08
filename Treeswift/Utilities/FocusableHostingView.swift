//
//  FocusableHostingView.swift
//  Treeswift
//
//  Invisible NSView background for tree keyboard navigation using AppKit first responder
//

import AppKit
import SwiftUI

/// Invisible NSView that can become first responder and handle keyboard events
class FocusableNSView: NSView {
	fileprivate var onArrowKey: ((KeyboardKey) -> Void)?
	fileprivate var isInLayout = false

	fileprivate enum KeyboardKey {
		case up, down
	}

	override var acceptsFirstResponder: Bool { true }

	override func layout() {
		if isInLayout {
			print("[FocusableNSView] ⚠️ REENTRANT layout detected")
			Thread.callStackSymbols.prefix(15).forEach { print("  \($0)") }
		}
		isInLayout = true
		super.layout()
		isInLayout = false
	}

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
	var claimFocusTrigger: Binding<Bool>?

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

		let shouldClaimForSelection = previousSelection != selectedID
		let shouldClaimForTrigger: Bool = if let trigger = claimFocusTrigger?.wrappedValue {
			trigger != previousTrigger && trigger
		} else {
			false
		}

		// Log whether updateNSView is being called during a layout pass
		if nsView.isInLayout {
			print("[FocusClaimingView] ⚠️ updateNSView called during layout pass")
			Thread.callStackSymbols.prefix(15).forEach { print("  \($0)") }
		}

		if shouldClaimForSelection || shouldClaimForTrigger {
			let reason = shouldClaimForSelection ? "selection changed" : "trigger fired"
			print("[FocusClaimingView] Scheduling makeFirstResponder (reason: \(reason))")
			context.coordinator.perform(
				#selector(Coordinator.claimFirstResponder(_:)),
				with: nsView,
				afterDelay: 0
			)
		}
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(selectedID: $selectedID, visibleItems: visibleItems, claimFocusTrigger: claimFocusTrigger)
	}

	class Coordinator: NSObject {
		fileprivate var selectedID: Binding<String?>
		private var visibleItems: [String]
		fileprivate var claimFocusTrigger: Binding<Bool>?

		fileprivate init(selectedID: Binding<String?>, visibleItems: [String], claimFocusTrigger: Binding<Bool>?) {
			self.selectedID = selectedID
			self.visibleItems = visibleItems
			self.claimFocusTrigger = claimFocusTrigger
		}

		fileprivate func updateBindings(
			selectedID: Binding<String?>,
			visibleItems: [String],
			claimFocusTrigger: Binding<Bool>?
		) {
			self.selectedID = selectedID
			self.visibleItems = visibleItems
			self.claimFocusTrigger = claimFocusTrigger
		}

		@objc fileprivate func claimFirstResponder(_ nsView: FocusableNSView) {
			print("[FocusClaimingView] Executing makeFirstResponder (isInLayout: \(nsView.isInLayout))")
			nsView.window?.makeFirstResponder(nsView)
		}

		fileprivate func handleArrowKey(_ key: FocusableNSView.KeyboardKey) {
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
