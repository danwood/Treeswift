//
//  ConfigurationFormView.swift
//  Treeswift
//
//  Form view for editing configuration settings
//  Following macOS layout guidelines from https://marioaguzman.github.io/design/layoutguidelines/
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationFormView: View {
	@Binding var configuration: PeripheryConfiguration
	@Binding var isLoadingSchemes: Bool
	@FocusState.Binding var focusedField: ContentColumnView.FocusableField?
	@Binding var layoutSettings: TreeLayoutSettings
	@State private var isFileDropTargeted = false
	@State private var availableSchemes: [String] = []
	@State private var isOptionsExpanded = false
	@State private var isBuildArgsEnabled = false
	@State private var isLayoutExpanded = false

	var body: some View {
		Form {
			// MARK: - Project Section

			LabeledContent {
				HStack(spacing: 8) {
					Spacer()

					// Project file display with icon
					if let projectPath = configuration.project {
						HStack(spacing: 4) {
							if let icon = iconForFile(at: projectPath) {
								Image(nsImage: icon)
									.resizable()
									.frame(width: 16, height: 16)
							}
							Text(displayNameForPath(projectPath))
								.lineLimit(1)
								.truncationMode(.middle)
						}
					} else {
						Text("No project selected")
							.foregroundStyle(.secondary)
					}

					/*
					 File Picker Implementation Note
					 ================================

					 We use NSOpenPanel directly instead of SwiftUI's .fileImporter because:

					 1. Package Handling Bug: SwiftUI's .fileImporter doesn't properly handle
					    packages (like .xcodeproj) as files. When using .fileDialogDefaultDirectory
					    with a package path, the dialog navigates INTO the package instead of
					    showing the parent folder with the package as a selectable file.

					 2. treatsFilePackagesAsDirectories: NSOpenPanel has a property to control
					    package behavior, but it's buggy with the modern allowedContentTypes API.
					    Setting treatsFilePackagesAsDirectories = false is IGNORED when using
					    allowedContentTypes with UTType.

					 3. Workaround: We use the deprecated allowedFileTypes property instead,
					    which correctly respects treatsFilePackagesAsDirectories = false.
					    This ensures packages are treated as single selectable files, not
					    directories to navigate into.

					 References:
					 - Apple Developer Forums: https://forums.developer.apple.com/forums/thread/738688
					 - Stack Overflow: https://stackoverflow.com/questions/72749915
					 */
					Button("Choose…") {
						showNSOpenPanel()
					}
				}
			} label: {
				Text("Project:")
			}
			.padding(.vertical, 4)
			.padding(.horizontal, 8)
			.background(
				RoundedRectangle(cornerRadius: 6)
					.fill(isFileDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 6)
					.stroke(isFileDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
			)
			.padding(.vertical, -4)
			.padding(.horizontal, -8)
			.onDrop(of: [.fileURL], isTargeted: $isFileDropTargeted) { providers in
				handleDrop(providers: providers)
			}

			// MARK: - Schemes Section

			if configuration.projectType == .xcode {
				LabeledContent {
					SchemePopoverButton(
						availableSchemes: availableSchemes,
						selectedSchemes: $configuration.schemes,
						isLoading: isLoadingSchemes
					)
				} label: {
					Text("Schemes:")
				}
			}

			// MARK: - Build Arguments Section

			LabeledContent {
				TextField("Build arguments", text: buildArgumentsBinding)
					.textFieldStyle(.roundedBorder)
					.labelsHidden()
					.focused($focusedField, equals: .buildArgs)
					.disabled(!isBuildArgsEnabled)
			} label: {
				Text("Build Args:")
			}

			// MARK: - Options Section

			optionsDisclosureGroup

			// MARK: - Tree Layout Section

			// ONLY USE IF I AM TWEAKING LAYOUT
			// layoutDisclosureGroup
		}
		.formStyle(.grouped)
		.onChange(of: configuration.project) { _, _ in
			loadSchemesSynchronously()
		}
		.task(id: configuration.project) {
			await loadSchemesAsynchronously()
		}
		.onAppear {
			loadSchemesSynchronously()
		}
		.task {
			try? await Task.sleep(for: .milliseconds(100))
			isBuildArgsEnabled = true
		}
	}

	// MARK: - Computed Properties

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

		if enabled.isEmpty {
			return "None"
		} else {
			return enabled.joined(separator: ", ")
		}
	}

	private var buildArgumentsBinding: Binding<String> {
		Binding(
			get: {
				configuration.buildArguments.joined(separator: " ")
			},
			set: { newValue in
				configuration.buildArguments = newValue
					.split(separator: " ")
					.map { String($0) }
					.filter { !$0.isEmpty }
			}
		)
	}

	// MARK: - View Components

	/**
	 Disclosure group for periphery scan options.
	 Displays a collapsible section with toggles for exclude tests, skip build, clean build,
	 verbose mode, and console logging. Shows a summary of enabled options when collapsed.
	 */
	private var optionsDisclosureGroup: some View {
		DisclosureGroup(
			isExpanded: $isOptionsExpanded,
			content: {
				VStack(alignment: .leading, spacing: 12) {
					Toggle("Exclude Tests", isOn: $configuration.excludeTests)
					Toggle("Skip Build", isOn: $configuration.skipBuild)
					Toggle("Clean Build", isOn: $configuration.cleanBuild)
					Toggle("Verbose", isOn: $configuration.isVerbose)
					Toggle("Log to Console", isOn: $configuration.shouldLogToConsole)
				}
				.padding(.leading, 20)
				.padding(.top, 8)
			},
			label: {
				LabeledContent {
					if !isOptionsExpanded {
						Text(optionsSummary)
							.foregroundStyle(hasOptionsEnabled ? .primary : .secondary)
							.multilineTextAlignment(.trailing)
							.frame(maxWidth: .infinity, alignment: .trailing)
					}
				} label: {
					Text("Options:")
				}
			}
		)
	}

	/**
	 Disclosure group for tree layout settings.
	 Provides sliders to adjust visual parameters of the tree view including indent per level,
	 leaf node offset, row padding, and chevron width.
	 */
	// periphery:ignore
	private var layoutDisclosureGroup: some View {
		DisclosureGroup(
			isExpanded: $isLayoutExpanded,
			content: {
				VStack(alignment: .leading, spacing: 12) {
					VStack(alignment: .leading, spacing: 4) {
						Text("Indent Per Level: \(Int(layoutSettings.indentPerLevel))")
							.font(.caption)
							.foregroundStyle(.secondary)
						Slider(value: $layoutSettings.indentPerLevel, in: 0 ... 40, step: 1)
					}

					VStack(alignment: .leading, spacing: 4) {
						Text("Leaf Node Offset: \(Int(layoutSettings.leafNodeOffset))")
							.font(.caption)
							.foregroundStyle(.secondary)
						Slider(value: $layoutSettings.leafNodeOffset, in: 0 ... 30, step: 1)
					}

					VStack(alignment: .leading, spacing: 4) {
						Text("Row Vertical Padding: \(Int(layoutSettings.rowVerticalPadding))")
							.font(.caption)
							.foregroundStyle(.secondary)
						Slider(value: $layoutSettings.rowVerticalPadding, in: 0 ... 12, step: 1)
					}

					VStack(alignment: .leading, spacing: 4) {
						Text("Chevron Width: \(Int(layoutSettings.chevronWidth))")
							.font(.caption)
							.foregroundStyle(.secondary)
						Slider(value: $layoutSettings.chevronWidth, in: 8 ... 20, step: 1)
					}
				}
				.padding(.leading, 20)
				.padding(.top, 8)
			},
			label: {
				LabeledContent {
					if !isLayoutExpanded {
						Text("Tree Layout")
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.trailing)
							.frame(maxWidth: .infinity, alignment: .trailing)
					}
				} label: {
					Text("Layout:")
				}
			}
		)
	}

	// MARK: - Helpers

	// Try to load schemes synchronously from cache to avoid UI flicker
	private func loadSchemesSynchronously() {
		guard configuration.projectType == .xcode else {
			availableSchemes = []
			return
		}

		guard let projectPath = configuration.project else {
			availableSchemes = []
			return
		}

		if let cachedSchemes = XcodeSchemeReader.cachedSchemes(forProjectAt: projectPath) {
			availableSchemes = cachedSchemes
			isLoadingSchemes = false
		}
	}

	// Load schemes asynchronously, querying xcodebuild if needed
	private func loadSchemesAsynchronously() async {
		guard configuration.projectType == .xcode else {
			availableSchemes = []
			return
		}

		guard let projectPath = configuration.project else {
			availableSchemes = []
			return
		}

		// If we already have cached schemes loaded synchronously, don't show loading state
		if availableSchemes.isEmpty {
			isLoadingSchemes = true
		}

		availableSchemes = await XcodeSchemeReader.schemes(forProjectAt: projectPath)
		isLoadingSchemes = false

		// Auto-select the scheme if there's only one and none is currently selected
		if availableSchemes.count == 1, configuration.schemes.isEmpty {
			configuration.schemes = availableSchemes
		}
	}

	private func displayNameForPath(_ path: String) -> String {
		if configuration.projectType == .swiftPackage {
			// For SPM projects, show "FolderName/Package.swift"
			let url = URL(fileURLWithPath: path)
			let folderName = url.deletingLastPathComponent().lastPathComponent
			let fileName = url.lastPathComponent
			return "\(folderName)/\(fileName)"
		} else {
			// For Xcode projects, show just the filename
			return FileManager.default.displayName(atPath: path)
		}
	}

	private func iconForFile(at path: String) -> NSImage? {
		NSWorkspace.shared.icon(forFile: path)
	}

	private func handleDrop(providers: [NSItemProvider]) -> Bool {
		guard let provider = providers.first else { return false }

		provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
			guard let data = item as? Data,
			      let url = URL(dataRepresentation: data, relativeTo: nil) else {
				return
			}

			Task { @MainActor in
				let projectURL: URL?
				let projectType: ProjectType?

				if url.isValidProjectFile {
					// It's a project/workspace bundle or Package.swift - use directly
					projectURL = url
					projectType = url.detectedProjectType
				} else if url.hasDirectoryPath {
					// It's a folder - search for project files inside
					let fm = FileManager.default

					// Check for .xcodeproj or .xcworkspace first (priority)
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
					} else {
						// No valid project found
						projectURL = nil
						projectType = nil
					}
				} else {
					// Not a valid project
					projectURL = nil
					projectType = nil
				}

				guard let projectURL, let projectType else {
					return
				}

				// Invalidate cache for old project if it exists
				SchemeCache.shared.invalidateIfNeeded(path: configuration.project)
				configuration.projectType = projectType
				configuration.project = projectURL.path
			}
		}

		return true
	}

	private func handleFileSelection(_ result: Result<[URL], Error>) {
		guard case let .success(urls) = result,
		      let url = urls.first else {
			return
		}

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
			} else {
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

		guard let projectURL, let projectType else {
			return
		}

		// Invalidate cache for old project if it exists
		SchemeCache.shared.invalidateIfNeeded(path: configuration.project)
		configuration.projectType = projectType
		configuration.project = projectURL.path
	}

	private func showNSOpenPanel() {
		// Invalidate cache for current project before showing picker
		SchemeCache.shared.invalidateIfNeeded(path: configuration.project)

		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = false
		panel.canChooseFiles = true
		panel.canChooseDirectories = false

		/*
		 CRITICAL: Set treatsFilePackagesAsDirectories = false to treat packages
		 (like .xcodeproj) as single selectable files, not as navigable directories
		 */
		panel.treatsFilePackagesAsDirectories = false

		/*
		 WORKAROUND: Use deprecated allowedFileTypes instead of allowedContentTypes
		 because the modern API ignores treatsFilePackagesAsDirectories = false.
		 This is a known bug in NSOpenPanel.
		 */
		panel.allowedFileTypes = ["xcodeproj", "xcworkspace", "swift"]

		/*
		 Set initial directory to parent of current project, or home directory.
		 Note: We cannot pre-select the specific .xcodeproj file because setting
		 directoryURL to the package path causes NSOpenPanel to navigate INTO the
		 package as a directory, despite treatsFilePackagesAsDirectories = false.
		 Apple removed official pre-selection APIs in 10.6 for security reasons.
		 */
		if let projectPath = configuration.project {
			let parentURL = URL(fileURLWithPath: projectPath).deletingLastPathComponent()
			panel.directoryURL = parentURL
		} else {
			panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
		}

		panel.message = "Select an Xcode project (.xcodeproj, .xcworkspace) or Swift Package (Package.swift)"

		// Show the panel
		if panel.runModal() == .OK, let url = panel.url {
			handleFileSelection(.success([url]))
		}
	}
}
