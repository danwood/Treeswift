import SwiftUI

struct OptionsDisclosureGroup: View {
	@Binding var isExpanded: Bool
	@Binding var configuration: PeripheryConfiguration

	private var hasOptionsEnabled: Bool {
		configuration.excludeTests ||
			configuration.skipBuild ||
			configuration.cleanBuild ||
			configuration.isVerbose ||
			configuration.shouldLogToConsole
	}

	private var optionsSummary: String {
		var enabled: [String] = []
		if configuration.excludeTests { enabled.append("Exclude Tests") }
		if configuration.skipBuild { enabled.append("Skip Build") }
		if configuration.cleanBuild { enabled.append("Clean Build") }
		if configuration.isVerbose { enabled.append("Verbose") }
		if configuration.shouldLogToConsole { enabled.append("Log to Console") }
		return enabled.isEmpty ? "None" : enabled.joined(separator: ", ")
	}

	var body: some View {
		LabeledContent {
			if !isExpanded {
				Text(optionsSummary)
					.foregroundStyle(hasOptionsEnabled ? .primary : .secondary)
					.multilineTextAlignment(.trailing)
					.frame(maxWidth: .infinity, alignment: .trailing)
			}
		} label: {
			Button {
				isExpanded.toggle()
			} label: {
				HStack(spacing: 4) {
					Image(systemName: "chevron.right")
						.font(.caption2.weight(.bold))
						.foregroundStyle(.secondary)
						.rotationEffect(.degrees(isExpanded ? 90 : 0))
						.animation(.easeInOut(duration: 0.2), value: isExpanded)
					Text("Options:")
				}
			}
			.buttonStyle(.plain)
		}

		if isExpanded {
			VStack(alignment: .leading, spacing: 12) {
				Toggle("Exclude Tests", isOn: $configuration.excludeTests)
				Toggle("Skip Build", isOn: $configuration.skipBuild)
				Toggle("Clean Build", isOn: $configuration.cleanBuild)
				Toggle("Verbose", isOn: $configuration.isVerbose)
				Toggle("Log to Console", isOn: $configuration.shouldLogToConsole)
			}
			.padding(.leading, 20)
		}
	}
}
