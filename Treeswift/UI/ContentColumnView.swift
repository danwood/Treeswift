//
//  ContentColumnView.swift
//  Treeswift
//
//  Content column showing configuration form and scan results
//

import SwiftUI
import PeripheryKit
import SourceGraph

struct ContentColumnView: View {
	@Binding var configuration: PeripheryConfiguration
	var scanState: ScanState
	let onUpdate: (PeripheryConfiguration) -> Void
	@Binding var filterState: FilterState
	@Binding var layoutSettings: TreeLayoutSettings
	@Binding var peripheryTabSelectedID: String?
	@Binding var filesTabSelectedID: String?
	@Binding var treeTabSelectedID: String?
	@Binding var viewExtensionsTabSelectedID: String?
	@Binding var sharedTabSelectedID: String?
	@Binding var orphansTabSelectedID: String?
	@Binding var previewOrphansTabSelectedID: String?
	@Binding var bodyGetterTabSelectedID: String?
	@Binding var unattachedTabSelectedID: String?

	@State private var isLoadingSchemes = false

	enum FocusableField: Hashable {
		case buildArgs
		case buildScanButton
	}
	@FocusState private var focusedField: FocusableField?

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 0) {
				ConfigurationFormView(
					configuration: $configuration,
					isLoadingSchemes: $isLoadingSchemes,
					focusedField: $focusedField,
					layoutSettings: $layoutSettings
				)
					.onChange(of: configuration) { _, newValue in
						onUpdate(newValue)
					}

				if scanState.isScanning {
					HStack(spacing: 8) {
						ProgressView()
							.controlSize(.small)

						Text(scanState.scanStatus)
							.foregroundStyle(.secondary)
							.font(.callout)

						Spacer()
					}
					.padding(.horizontal, 20)
					.padding(.vertical, 12)
					.background(Color(nsColor: .controlBackgroundColor))
					.transition(.move(edge: .top).combined(with: .opacity))
				}

				if let error = scanState.errorMessage {
					Text("Error: \(error)")
						.foregroundStyle(.red)
						.textSelection(.enabled)
						.padding()
						.background(Color.red.opacity(0.1))
						.clipShape(.rect(cornerRadius:8))
						.padding()
				}

				if !scanState.scanResults.isEmpty || scanState.sourceGraph != nil {
					ResultsTabView(
						treeNodes: scanState.treeNodes,
						scanResults: scanState.scanResults,
						sourceGraph: scanState.sourceGraph,
						treeSection: scanState.treeSection,
						viewExtensionsSection: scanState.viewExtensionsSection,
						sharedSection: scanState.sharedSection,
						orphansSection: scanState.orphansSection,
						previewOrphansSection: scanState.previewOrphansSection,
						bodyGetterSection: scanState.bodyGetterSection,
						unattachedSection: scanState.unattachedSection,
						fileTreeNodes: scanState.fileTreeNodes,
						projectPath: scanState.projectPath,
						filterState: $filterState,
						peripheryTabSelectedID: $peripheryTabSelectedID,
						filesTabSelectedID: $filesTabSelectedID,
						treeTabSelectedID: $treeTabSelectedID,
						viewExtensionsTabSelectedID: $viewExtensionsTabSelectedID,
						sharedTabSelectedID: $sharedTabSelectedID,
						orphansTabSelectedID: $orphansTabSelectedID,
						previewOrphansTabSelectedID: $previewOrphansTabSelectedID,
						bodyGetterTabSelectedID: $bodyGetterTabSelectedID,
						unattachedTabSelectedID: $unattachedTabSelectedID
					)
					.environment(\.refreshFileTree, { scanState.refreshFileTree() })
				} else if !scanState.isScanning {
					Text("Run a scan to see results")
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.foregroundStyle(.secondary)
						.padding()
				}
			}
		}
		.environment(\.peripheryFilterState, filterState)
		.frame(minWidth: LayoutConstants.contentColumnMinWidth, minHeight: 400)
		.animation(.easeInOut(duration: 0.3), value: isLoadingSchemes)
		.animation(.easeInOut(duration: 0.3), value: scanState.isScanning)
		.toolbar {
			ToolbarItem(placement: .automatic) {
				Button(scanState.isScanning ? "Stop" : "Build & Scan", systemImage: scanState.isScanning ? "stop.fill" : "play.fill", action: scanState.isScanning ? scanState.stopScan : {
					peripheryTabSelectedID = nil
					filesTabSelectedID = nil
					treeTabSelectedID = nil
					viewExtensionsTabSelectedID = nil
					sharedTabSelectedID = nil
					orphansTabSelectedID = nil
					previewOrphansTabSelectedID = nil
					bodyGetterTabSelectedID = nil
					unattachedTabSelectedID = nil
					scanState.startScan(configuration: configuration)
				})
				.labelStyle(.titleAndIcon)
				.buttonStyle(.borderless)
				.frame(maxWidth: .infinity)
				.keyboardShortcut(.defaultAction)
				.focused($focusedField, equals: .buildScanButton)
				.disabled(!scanState.isScanning && configuration.projectType == .xcode && (isLoadingSchemes || configuration.schemes.isEmpty))
				.widthPreserving {
					Button("Build & Scan", systemImage: "play.fill", action: {})
						.labelStyle(.titleAndIcon)
					Button("Stop", systemImage: "stop.fill", action: {})
						.labelStyle(.titleAndIcon)
				}
			}
		}
	}
}

#Preview {
	@Previewable @State var config = PeripheryConfiguration.demo()
	@Previewable @State var peripheryID: String?
	@Previewable @State var filesID: String?
	@Previewable @State var treeID: String?
	@Previewable @State var viewExtensionsID: String?
	@Previewable @State var sharedID: String?
	@Previewable @State var orphansID: String?
	@Previewable @State var previewOrphansID: String?
	@Previewable @State var bodyGetterID: String?
	@Previewable @State var unattachedID: String?
	@Previewable @State var filterState = FilterState()
	@Previewable @State var layoutSettings = TreeLayoutSettings()
	let scanState = ScanState(configurationID: config.id)
	ContentColumnView(
		configuration: $config,
		scanState: scanState,
		onUpdate: { _ in },
		filterState: $filterState,
		layoutSettings: $layoutSettings,
		peripheryTabSelectedID: $peripheryID,
		filesTabSelectedID: $filesID,
		treeTabSelectedID: $treeID,
		viewExtensionsTabSelectedID: $viewExtensionsID,
		sharedTabSelectedID: $sharedID,
		orphansTabSelectedID: $orphansID,
		previewOrphansTabSelectedID: $previewOrphansID,
		bodyGetterTabSelectedID: $bodyGetterID,
		unattachedTabSelectedID: $unattachedID
	)
}
