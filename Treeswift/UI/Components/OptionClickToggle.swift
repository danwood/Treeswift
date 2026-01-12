//
//  OptionClickToggle.swift
//  Treeswift
//
//  Reusable toggle component with option-click multi-select behavior
//

import SwiftUI

struct OptionClickToggle<Content: View>: View {
	let isEnabled: Binding<Bool>
	let onOptionClick: (Bool) -> Void
	let content: Content

	init(
		isEnabled: Binding<Bool>,
		onOptionClick: @escaping (Bool) -> Void,
		@ViewBuilder content: () -> Content
	) {
		self.isEnabled = isEnabled
		self.onOptionClick = onOptionClick
		self.content = content()
	}

	var body: some View {
		Toggle(isOn: Binding(
			get: { isEnabled.wrappedValue },
			set: { newValue in
				if NSEvent.modifierFlags.contains(.option) {
					onOptionClick(newValue)
				} else {
					isEnabled.wrappedValue = newValue
				}
			}
		)) {
			content
		}
		.toggleStyle(.checkbox)
	}
}
