//
//  ScanState.swift
//  Treeswift
//
//  Per-configuration scan state management
//  Maintains scan results, progress, and task state for a single configuration
//

import SwiftUI
import PeripheryKit
import Configuration
import SourceGraph
import Logger
import Foundation

@Observable
@MainActor
final class ScanState {
	// Scan results - automatically observable with @Observable
	var scanResults: [ScanResult] = []
	var sourceGraph: SourceGraph? = nil
	var treeNodes: [TreeNode] = []
	var treeSection: CategoriesNode? = nil
	var viewExtensionsSection: CategoriesNode? = nil
	var sharedSection: CategoriesNode? = nil
	var orphansSection: CategoriesNode? = nil
	var previewOrphansSection: CategoriesNode? = nil
	var bodyGetterSection: CategoriesNode? = nil
	var unattachedSection: CategoriesNode? = nil
	var fileTreeNodes: [FileBrowserNode] = [] {
		didSet {
			fileNodesLookup = Self.buildFileNodesLookup(from: fileTreeNodes)
		}
	}
	var categoriesOutput: String = ""
	var projectPath: String? = nil

	// Lookup dictionaries for O(1) node access
	var fileNodesLookup: [String: FileBrowserNode] = [:]

	// Scan progress state
	var isScanning: Bool = false
	var scanStatus: String = "Scanning…"
	var errorMessage: String? = nil

	// Task management
	var scanTask: Task<Void, Never>? = nil
	let scanner = PeripheryScanRunner()

	// Background task tracking
	var backgroundTasks: [Task<Void, Never>] = []
	var backgroundTasksTotal: Int = 0
	var backgroundTasksCompleted: Int = 0
	var streamCompleted: Bool = false

	init(configurationID _: UUID) {
	}

	/// Runs a complete Periphery scan with progressive streaming
	///
	/// This method consumes the AsyncThrowingStream from PeripheryScanRunner.runFullScanWithStreaming()
	/// to provide progressive UI updates:
	/// - Phase 1: Scan completes → tabs appear immediately
	/// - Phase 2: Post-processing streams in progressively
	///   - Categories sections (7 total) build sequentially
	func startScan(configuration: PeripheryConfiguration) {
		isScanning = true
		scanStatus = "Scanning…"
		errorMessage = nil
		scanResults = []
		sourceGraph = nil
		treeNodes = []
		treeSection = nil
		viewExtensionsSection = nil
		sharedSection = nil
		orphansSection = nil
		previewOrphansSection = nil
		bodyGetterSection = nil
		unattachedSection = nil
		fileTreeNodes = []
		categoriesOutput = ""
		projectPath = configuration.project
		backgroundTasks.removeAll()
		backgroundTasksTotal = 0
		backgroundTasksCompleted = 0
		streamCompleted = false

		// Convert PeripheryConfiguration to Periphery's Configuration object
		let config = configuration.toConfiguration()
		let projectPath = configuration.project
		let projectType = configuration.projectType
		let projectDirectory = configuration.projectDirectory
		let logToConsole = configuration.shouldLogToConsole

		scanTask = Task {
			do {
				// Consume the progressive stream
				for try await progress in scanner.runFullScanWithStreaming(
					configuration: config,
					projectPath: projectPath,
					projectType: projectType,
					projectDirectory: projectDirectory
				) {
					switch progress {
					case .statusUpdate(let status):
						// Update UI status and log to console
						scanStatus = status
						"* \(status)".logToConsole()

					case .scanComplete(let results, let graph):
						// Phase 1 complete - tabs can appear now
						scanResults = results
						sourceGraph = graph

						// Log formatted periphery output to console if enabled
						if logToConsole && !results.isEmpty {
							Task.detached(priority: .utility) {
								do {
									// Create logger for formatting (matches PeripheryScanRunner pattern)
									let logger = Logger(quiet: false, verbose: false, colorMode: .never)
									let formatter = config.outputFormat.formatter.init(configuration: config, logger: logger)
									if let output = try formatter.format(results, colored: false) {
										"=== Periphery Output ===\n\(output)".logToConsole()
									}
								} catch {
									"Error formatting periphery output: \(error.localizedDescription)".logToConsole()
								}
							}
						}

						// Build tree nodes in background for Periphery tab
						if !results.isEmpty, let path = projectPath {
							let projectRoot = URL(fileURLWithPath: path).deletingLastPathComponent().path
							let treeTask = Task.detached(priority: .userInitiated) {
								let nodes = ResultsTreeBuilder.buildTree(from: results, projectRoot: projectRoot)
								"* ✓ Periphery tree built".logToConsole()
								await MainActor.run {
									self.treeNodes = nodes
									self.onBackgroundTaskComplete()
								}
							}
							backgroundTasks.append(treeTask)
							backgroundTasksTotal += 1

							// Scan file system in background for Files tab
							let fileSystemTask = Task.detached(priority: .userInitiated) {
								let scanner = FileSystemScanner()
								let fileAnalyzer = FileTypeAnalyzer()
								let fileWarningAnalyzer = FileWarningAnalyzer()
								let folderAnalyzer = FolderTypeAnalyzer()
								do {
									let rawFileNodes = try await scanner.scanProject(at: path)
									let fileNodes = Self.computeContainsSwiftFiles(nodes: rawFileNodes)
									"* ✓ File system scanned".logToConsole()

									await MainActor.run {
										self.fileTreeNodes = fileNodes
									}

									// Capture current scan results and designation manager for type analysis
									let scanResults = await MainActor.run { self.scanResults }
									let typeEnrichedNodes = await fileAnalyzer.enrichFilesWithTypeInfo(
										fileNodes: fileNodes,
										graph: graph,
										scanResults: scanResults
									)
									"* ✓ Type analysis complete".logToConsole()

									// Analyze file-level warnings for shared code
									let fileWarningEnrichedNodes = await fileWarningAnalyzer.analyzeFiles(
										nodes: typeEnrichedNodes,
										graph: graph
									)
									"* ✓ File warning analysis complete".logToConsole()

									// Perform folder analysis
									let folderEnrichedNodes = await folderAnalyzer.analyzeFolders(
										nodes: fileWarningEnrichedNodes,
										graph: graph,
										projectPath: path
									)
									"* ✓ Folder analysis complete".logToConsole()

									await MainActor.run {
										withAnimation(.easeInOut(duration: 0.3)) {
											self.fileTreeNodes = folderEnrichedNodes
										}
										self.onBackgroundTaskComplete()
									}
								} catch {
									"* ⚠ File system scan failed: \(error.localizedDescription)".logToConsole()
									await MainActor.run {
										self.onBackgroundTaskComplete()
									}
								}
							}
							backgroundTasks.append(fileSystemTask)
							backgroundTasksTotal += 1
						}

					case .categoriesSectionAdded(let section):
						// Route Categories section to appropriate property based on ID
						guard case .section(let sectionNode) = section else { continue }
						switch sectionNode.id {
						case .hierarchy:
							treeSection = section
						case .viewExtensions:
							viewExtensionsSection = section
						case .shared:
							sharedSection = section
						case .orphaned:
							orphansSection = section
						case .previewOrphaned:
							previewOrphansSection = section
						case .bodyGetter:
							bodyGetterSection = section
						case .unattached:
							unattachedSection = section
						}
					}
				}

				// Stream complete - but background tasks may still be running
				streamCompleted = true
				scanStatus = "Processing results..."
				"* ✓ Scan workflow complete".logToConsole()
				checkIfFullyComplete()

			} catch is CancellationError {
				// Cancel all background tasks
				for task in backgroundTasks {
					task.cancel()
				}
				backgroundTasks.removeAll()

				isScanning = false
				scanTask = nil
				streamCompleted = false
				backgroundTasksTotal = 0
				backgroundTasksCompleted = 0
			} catch {
				// Cancel all background tasks on error
				for task in backgroundTasks {
					task.cancel()
				}
				backgroundTasks.removeAll()

				errorMessage = error.localizedDescription
				isScanning = false
				scanTask = nil
				streamCompleted = false
				backgroundTasksTotal = 0
				backgroundTasksCompleted = 0
			}
		}
	}

	func stopScan() {
		// Cancel main scan task
		scanTask?.cancel()
		scanTask = nil

		// Cancel all background tasks
		for task in backgroundTasks {
			task.cancel()
		}
		backgroundTasks.removeAll()

		// Reset state
		isScanning = false
		streamCompleted = false
		backgroundTasksTotal = 0
		backgroundTasksCompleted = 0
	}

	// MARK: - Background Task Completion Tracking

	private func onBackgroundTaskComplete() {
		backgroundTasksCompleted += 1
		checkIfFullyComplete()
	}

	private func checkIfFullyComplete() {
		if streamCompleted && backgroundTasksCompleted >= backgroundTasksTotal {
			isScanning = false
			scanStatus = "Scan complete"
			scanTask = nil
		}
	}

	// MARK: - File Tree Refresh

	func refreshFileTree() {
		guard let path = projectPath, let graph = sourceGraph else { return }

		Task.detached(priority: .userInitiated) {
			let scanner = FileSystemScanner()
			let fileAnalyzer = FileTypeAnalyzer()
			let fileWarningAnalyzer = FileWarningAnalyzer()
			let folderAnalyzer = FolderTypeAnalyzer()

			do {
				let rawFileNodes = try await scanner.scanProject(at: path)
				let fileNodes = Self.computeContainsSwiftFiles(nodes: rawFileNodes)

				// Capture current scan results for type analysis
				let scanResults = await MainActor.run { self.scanResults }
				let typeEnrichedNodes = await fileAnalyzer.enrichFilesWithTypeInfo(
					fileNodes: fileNodes,
					graph: graph,
					scanResults: scanResults
				)

				// Analyze file-level warnings for shared code
				let warningEnrichedNodes = await fileWarningAnalyzer.analyzeFiles(
					nodes: typeEnrichedNodes,
					graph: graph
				)

				// Analyze folder structure
				let folderEnrichedNodes = await folderAnalyzer.analyzeFolders(
					nodes: warningEnrichedNodes,
					graph: graph,
					projectPath: path
				)

				await MainActor.run {
					self.fileTreeNodes = folderEnrichedNodes
				}
			} catch {
				"* ✗ File tree refresh failed: \(error.localizedDescription)".logToConsole()
			}
		}
	}

	// MARK: - Lookup Dictionary Builders

	private static func buildFileNodesLookup(from nodes: [FileBrowserNode]) -> [String: FileBrowserNode] {
		var lookup: [String: FileBrowserNode] = [:]
		buildFileNodesLookupRecursive(nodes: nodes, into: &lookup)
		return lookup
	}

	private static func buildFileNodesLookupRecursive(nodes: [FileBrowserNode], into lookup: inout [String: FileBrowserNode]) {
		for node in nodes {
			switch node {
			case .directory(let dir):
				lookup[dir.id] = node
				buildFileNodesLookupRecursive(nodes: dir.children, into: &lookup)
			case .file(let file):
				lookup[file.id] = node
			}
		}
	}

	// MARK: - containsSwiftFiles Computation

	private nonisolated static func computeContainsSwiftFiles(nodes: [FileBrowserNode]) -> [FileBrowserNode] {
		nodes.map { node in
			switch node {
			case .directory(var dir):
				let updatedChildren = computeContainsSwiftFiles(nodes: dir.children)
				dir.children = updatedChildren

				let hasSwiftFiles = updatedChildren.contains { child in
					switch child {
					case .file:
						true
					case .directory(let childDir):
						childDir.containsSwiftFiles
					}
				}
				dir.containsSwiftFiles = hasSwiftFiles
				return .directory(dir)
			case .file:
				return node
			}
		}
	}
}
