//
//  SchemePopoverButton.swift
//  Treeswift
//
//  Compact popover-based scheme selector for configuration forms
//

import SwiftUI

struct SchemePopoverButton: View {
	let availableSchemes: [String]
	@Binding var selectedSchemes: [String]
	let isLoading: Bool

	@State private var isPopoverPresented = false
	@State private var frozenButtonText: String = ""

	var body: some View {
		Button(action: {
			if !isPopoverPresented {
				frozenButtonText = buttonText
			}
			isPopoverPresented.toggle()
		}) {
			HStack(spacing: 4) {
				Text(displayedText)
					.foregroundStyle(textColor)
				Image(systemName: "chevron.down")
					.font(.caption2)
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(Color(nsColor: .controlBackgroundColor))
			.clipShape(.rect(cornerRadius: 4))
			.overlay(
				RoundedRectangle(cornerRadius: 4)
					.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
			)
		}
		.buttonStyle(.plain)
		.disabled(isLoading || availableSchemes.isEmpty)
		.popover(isPresented: $isPopoverPresented) {
			SchemeSelectionPopover(
				availableSchemes: availableSchemes,
				selectedSchemes: $selectedSchemes
			)
		}
	}

	private var displayedText: String {
		isPopoverPresented ? frozenButtonText : buttonText
	}

	private var buttonText: String {
		if isLoading {
			return "Loading…"
		} else if availableSchemes.isEmpty {
			return "(No Project Chosen)"
		} else if selectedSchemes.isEmpty {
			return "Choose schemes…"
		} else if selectedSchemes.count == 1 {
			return selectedSchemes[0]
		} else if selectedSchemes.count == 2 {
			return "\(selectedSchemes[0]), \(selectedSchemes[1])"
		} else {
			let additional = selectedSchemes.count - 2
			return "\(selectedSchemes[0]), \(selectedSchemes[1]), +\(additional) more"
		}
	}

	private var textColor: Color {
		if isLoading || availableSchemes.isEmpty {
			.secondary
		} else {
			.primary
		}
	}
}

private struct SchemeSelectionPopover: View {
	let availableSchemes: [String]
	@Binding var selectedSchemes: [String]

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 6) {
				ForEach(availableSchemes, id: \.self) { scheme in
					Toggle(scheme, isOn: Binding(
						get: { selectedSchemes.contains(scheme) },
						set: { isSelected in
							if isSelected {
								if !selectedSchemes.contains(scheme) {
									selectedSchemes.append(scheme)
								}
							} else {
								selectedSchemes.removeAll { $0 == scheme }
							}
						}
					))
					.simultaneousGesture(
						TapGesture(count: 1)
							.modifiers(.option)
							.onEnded {
								applyToAll(scheme: scheme)
							}
					)
				}
			}
		}
		.frame(maxHeight: 300)
		.padding(12)
		.frame(minWidth: 250, maxWidth: 400)
	}

	func applyToAll(scheme: String) {
		let willBeSelected = !selectedSchemes.contains(scheme)
		if willBeSelected {
			selectedSchemes = availableSchemes
		} else {
			selectedSchemes = []
		}
	}
}
