import AppKit
import SwiftUI

struct ConfigurationIconView: View {
	let config: PeripheryConfiguration

	var body: some View {
		if let projectPath = config.project {
			switch config.projectType {
			case .xcode:
				let image = NSWorkspace.shared.icon(forFile: projectPath)
				Image(nsImage: image)
					.resizable()
					.frame(width: 16, height: 16)
			case .swiftPackage:
				Text("📦")
					.font(.subheadline)
			}
		} else {
			Image(systemName: "folder")
				.foregroundStyle(.secondary)
		}
	}
}
