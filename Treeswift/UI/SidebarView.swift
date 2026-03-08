//
//  SidebarView.swift
//  Treeswift
//
//  Sidebar navigation for configuration list
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
	var configManager: ConfigurationManager
	var scanStateManager: ScanStateManager
	@Binding var selectedConfigID: UUID?
	@State private var isSidebarDropTargeted = false

	var body: some View {
		VStack(spacing: 0) {
			List(selection: $selectedConfigID) {
				ForEach(configManager.configurations) { config in
					NavigationLink(value: config.id) {
						let missing = isProjectMissing(config)
						HStack(spacing: 8) {
							ConfigurationIconView(config: config)
							Text(projectNameForConfig(config))
								.foregroundStyle(missing ? .secondary : .primary)
							Spacer()
							if missing {
								Image(systemName: "exclamationmark.triangle")
									.foregroundStyle(.secondary)
							}
						}
						.help(tooltipForConfig(config) ?? "")
					}
				}
				.onMove(perform: moveConfigurations)
			}
			.background(
				isSidebarDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear
			)
			.overlay {
				Rectangle()
					.stroke(isSidebarDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
					.padding(2)
			}
			.onDrop(of: [.fileURL], isTargeted: $isSidebarDropTargeted) { providers in
				handleSidebarDrop(providers: providers)
			}

			// +/- buttons at bottom of sidebar
			HStack(spacing: 0) {
				Button(action: addConfiguration) {
					Image(systemName: "plus")
						.frame(width: 20, height: 20)
						.contentShape(.rect)
				}
				.buttonStyle(.borderless)
				.padding(.leading, 8)

				Button(action: deleteSelectedConfiguration) {
					Image(systemName: "minus")
						.frame(width: 20, height: 20)
						.contentShape(.rect)
				}
				.buttonStyle(.borderless)
				.disabled(selectedConfigID == nil)

				Spacer()
			}
			.frame(height: 22)
			.background(.background)
		}
	}

	// MARK: - Actions

	private func addConfiguration() {
		let newConfig = PeripheryConfiguration(
			name: "New Configuration",
			project: nil,
			schemes: []
		)
		configManager.addConfiguration(newConfig)
		selectedConfigID = newConfig.id
	}

	private func deleteSelectedConfiguration() {
		guard let selectedID = selectedConfigID,
		      let index = configManager.configurations.firstIndex(where: { $0.id == selectedID }) else {
			return
		}

		configManager.deleteConfiguration(at: index, scanStateManager: scanStateManager)

		// Select a new configuration after deletion
		if !configManager.configurations.isEmpty {
			if index < configManager.configurations.count {
				selectedConfigID = configManager.configurations[index].id
			} else {
				selectedConfigID = configManager.configurations.last?.id
			}
		} else {
			selectedConfigID = nil
		}
	}

	private func moveConfigurations(from source: IndexSet, to destination: Int) {
		configManager.moveConfiguration(from: source, to: destination)
	}

	private func handleSidebarDrop(providers: [NSItemProvider]) -> Bool {
		guard let provider = providers.first else { return false }

		// NOTE: NSItemProvider.loadItem(forTypeIdentifier:) is the legacy callback API.
		// The modern replacement would be NSItemProvider.loadTransferable(type:) or
		// loadObject(ofClass:). However, neither cleanly handles the file URL → URL
		// conversion with proper sandbox security-scoped bookmark support on macOS.
		// The Task { @MainActor in } wrapping correctly bridges back to the main actor.
		// This is a known antipattern (Task created from non-@MainActor context) but
		// is safe here because we only mutate @MainActor state inside the Task block.
		provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
			guard let data = item as? Data,
			      let url = URL(dataRepresentation: data, relativeTo: nil) else {
				return
			}

			Task { @MainActor in
				guard let resolved = ProjectURLResolver.resolve(from: url) else { return }

				let projectName = resolved.projectType == .xcode
					? resolved.url.deletingPathExtension().lastPathComponent
					: resolved.url.deletingLastPathComponent().lastPathComponent

				let newConfig = PeripheryConfiguration(
					name: projectName,
					projectType: resolved.projectType,
					project: resolved.url.path,
					schemes: []
				)
				configManager.addConfiguration(newConfig)
				selectedConfigID = newConfig.id
			}
		}

		return true
	}

	// MARK: - Helpers

	private func isProjectMissing(_ config: PeripheryConfiguration) -> Bool {
		guard let projectPath = config.project else { return false }
		return !FileManager.default.fileExists(atPath: projectPath)
	}

	private func projectNameForConfig(_ config: PeripheryConfiguration) -> String {
		guard let projectPath = config.project else {
			return config.name
		}

		let url = URL(fileURLWithPath: projectPath)

		switch config.projectType {
		case .xcode:
			// For Xcode projects, show project name without extension
			return url.deletingPathExtension().lastPathComponent
		case .swiftPackage:
			// For SPM projects, show folder name (not "Package.swift")
			return url.deletingLastPathComponent().lastPathComponent
		}
	}

	private func tooltipForConfig(_ config: PeripheryConfiguration) -> String? {
		guard let projectPath = config.project else {
			return nil
		}

		// Use NSString method to abbreviate home directory with ~
		return (projectPath as NSString).abbreviatingWithTildeInPath
	}
}

#Preview {
	@Previewable @State var selectedID: UUID?
	NavigationSplitView {
		SidebarView(
			configManager: ConfigurationManager(),
			scanStateManager: ScanStateManager(),
			selectedConfigID: $selectedID
		)
	} detail: {
		Text("Detail")
	}
}
