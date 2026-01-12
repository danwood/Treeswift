//
//  SidebarView.swift
//  Treeswift
//
//  Sidebar navigation for configuration list
//

import SwiftUI
import AppKit
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
						HStack(spacing: 8) {
							iconForConfig(config)
							Text(projectNameForConfig(config))
						}
						.help(tooltipForConfig(config) ?? "")
					}
				}
				.onMove(perform: moveConfigurations)
			}
			.background(
				isSidebarDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear
			)
			.overlay(
				Rectangle()
					.stroke(isSidebarDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
					.padding(2)
			)
			.onDrop(of: [.fileURL], isTargeted: $isSidebarDropTargeted) { providers in
				handleSidebarDrop(providers: providers)
			}

			// +/- buttons at bottom of sidebar
			HStack(spacing: 0) {
				Button(action: addConfiguration) {
					Image(systemName: "plus")
						.frame(width: 20, height: 20)
				}
				.buttonStyle(.borderless)
				.padding(.leading, 8)

				Button(action: deleteSelectedConfiguration) {
					Image(systemName: "minus")
						.frame(width: 20, height: 20)
				}
				.buttonStyle(.borderless)
				.disabled(selectedConfigID == nil)

				Spacer()
			}
			.frame(height: 22)
			.background(Color(nsColor: .controlBackgroundColor))
		}
	}

	// MARK: - Actions

	func addConfiguration() {
		let newConfig = PeripheryConfiguration(
			name: "New Configuration",
			project: nil,
			schemes: []
		)
		configManager.addConfiguration(newConfig)
		selectedConfigID = newConfig.id
	}

	func deleteSelectedConfiguration() {
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

	func moveConfigurations(from source: IndexSet, to destination: Int) {
		configManager.moveConfiguration(from: source, to: destination)
	}

	func handleSidebarDrop(providers: [NSItemProvider]) -> Bool {
		guard let provider = providers.first else { return false }

		provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
			guard let data = item as? Data,
				  let url = URL(dataRepresentation: data, relativeTo: nil) else {
				return
			}

			Task { @MainActor in
				let projectURL: URL?
				let projectType: ProjectType?

				if url.hasDirectoryPath {
					// It's a folder - search for project files
					let fm = FileManager.default

					// Check for .xcodeproj first (priority)
					if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
					   let xcodeproj = contents.first(where: {
						   $0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace"
					   }) {
						projectURL = xcodeproj
						projectType = .xcode
					}
					// Check for Package.swift
					else if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
						projectURL = url.appendingPathComponent("Package.swift")
						projectType = .swiftPackage
					}
					else {
						// No valid project found
						projectURL = nil
						projectType = nil
					}
				} else {
					// It's a file - validate and detect type
					if url.isValidProjectFile {
						projectURL = url
						projectType = url.detectedProjectType
					} else {
						projectURL = nil
						projectType = nil
					}
				}

				guard let projectURL = projectURL, let projectType = projectType else {
					return
				}

				let projectName = projectType == .xcode
					? projectURL.deletingPathExtension().lastPathComponent
					: projectURL.deletingLastPathComponent().lastPathComponent

				let newConfig = PeripheryConfiguration(
					name: projectName,
					projectType: projectType,
					project: projectURL.path,
					schemes: []
				)
				configManager.addConfiguration(newConfig)
				selectedConfigID = newConfig.id
			}
		}

		return true
	}

	// MARK: - Helpers

	func projectNameForConfig(_ config: PeripheryConfiguration) -> String {
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

	func tooltipForConfig(_ config: PeripheryConfiguration) -> String? {
		guard let projectPath = config.project else {
			return nil
		}

		// Use NSString method to abbreviate home directory with ~
		return (projectPath as NSString).abbreviatingWithTildeInPath
	}

	@ViewBuilder
	func iconForConfig(_ config: PeripheryConfiguration) -> some View {
		if let projectPath = config.project {
			switch config.projectType {
			case .xcode:
				// Use NSWorkspace to get file icon for .xcodeproj
				let image = NSWorkspace.shared.icon(forFile: projectPath)
				Image(nsImage: image)
					.resizable()
					.frame(width: 16, height: 16)
			case .swiftPackage:
				// Use package emoji for SPM
				Text("📦")
					.font(.subheadline)
			}
		} else {
			// No project set - show generic icon
			Image(systemName: "folder")
				.foregroundStyle(.secondary)
		}
	}
}

#Preview {
	@Previewable @State var selectedID: UUID? = nil
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
