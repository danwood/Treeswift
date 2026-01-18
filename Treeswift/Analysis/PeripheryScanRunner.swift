//
//	PeripheryScanRunner.swift
//	Treeswift
//
//	Uses Periphery source code to perform scans
//	Core logic extracted from ScanCommand.run() for GUI use
//

import Configuration
import Extensions
import FilenameMatcher
import Foundation
import FrontendLib
import Logger
import PeripheryKit
import Shared
import SourceGraph
import SystemPackage

// Custom Shell that ensures PATH includes developer tools
private final class GUIShell: Shell {
	@discardableResult
	func exec(_ args: [String]) throws -> String {
		let (status, stdout, stderr) = try execute(args)

		if status == 0 {
			return stdout
		}

		throw PeripheryError.shellCommandFailed(
			cmd: args,
			status: status,
			output: [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n").trimmed
		)
	}

	@discardableResult
	func execStatus(_ args: [String]) throws -> Int32 {
		let (status, _, _) = try execute(args, captureOutput: false)
		return status
	}

	private func execute(
		_ cmd: [String],
		captureOutput: Bool = true
	) throws -> (Int32, String, String) {
		let process = Process()
		process.launchPath = "/bin/bash"
		process.arguments = ["-c", cmd.joined(separator: " ")]

		var stdoutPipe: Pipe?
		var stderrPipe: Pipe?

		if captureOutput {
			stdoutPipe = Pipe()
			stderrPipe = Pipe()
			process.standardOutput = stdoutPipe
			process.standardError = stderrPipe
		}

		process.launch()

		var standardOutput = ""
		var standardError = ""

		if let stdoutData = try stdoutPipe?.fileHandleForReading.readToEnd() {
			guard let stdoutStr = String(data: stdoutData, encoding: .utf8) else {
				throw PeripheryError.shellOutputEncodingFailed(
					cmd: cmd,
					encoding: .utf8
				)
			}
			standardOutput = stdoutStr
		}

		if let stderrData = try stderrPipe?.fileHandleForReading.readToEnd() {
			guard let stderrStr = String(data: stderrData, encoding: .utf8) else {
				throw PeripheryError.shellOutputEncodingFailed(
					cmd: cmd,
					encoding: .utf8
				)
			}
			standardError = stderrStr
		}

		process.waitUntilExit()
		return (process.terminationStatus, standardOutput, standardError)
	}

	required nonisolated init(logger: Logger) {
		// GUI apps don't inherit the full PATH from the shell
		// Add common locations for Xcode and developer tools
		var path = ProcessInfo.processInfo.environment["PATH"] ?? ""
		let additionalPaths = [
			"/usr/bin",
			"/bin",
			"/usr/sbin",
			"/sbin",
			"/usr/local/bin",
			"/opt/homebrew/bin",
			"/Applications/Xcode.app/Contents/Developer/usr/bin",
			"/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin",
			"/Library/Developer/CommandLineTools/usr/bin"
		]

		for additionalPath in additionalPaths {
			if !path.contains(additionalPath) {
				path = path.isEmpty ? additionalPath : "\(additionalPath):\(path)"
			}
		}

		setenv("PATH", path, 1)
	}
}

/// Progress events emitted during streaming scan execution
enum ScanProgress: Sendable {
	/// Phase 1 complete - scan results and source graph available
	case scanComplete([ScanResult], SourceGraph)

	/// Categories section completed and ready for display
	case categoriesSectionAdded(CategoriesNode)

	/// Status message for progress updates
	case statusUpdate(String)
}

/// Periphery scan execution engine - designed to run OFF the main thread
///
/// **Design:**
/// - Marked `Sendable` to enforce thread-safety (no mutable state, no data races)
/// - ALL methods marked `nonisolated` to prevent MainActor inference
///	  - Both async AND sync methods need `nonisolated` in Swift's concurrency model
///	  - Without it, Swift infers MainActor isolation based on call context
/// - All methods run on the caller's executor (background from Task.detached)
///
/// **Usage:**
/// Only call from background tasks (Task.detached) - never from MainActor context
final class PeripheryScanRunner: Sendable {
	// Internal class to bridge progress callbacks
	// Must be nonisolated to work with nonisolated scan methods
	private final class ProgressBridge: ScanProgressDelegate, @unchecked Sendable {
		let callback: @Sendable (String) -> Void

		nonisolated init(callback: @escaping @Sendable (String) -> Void) {
			self.callback = callback
		}

		nonisolated func didStartInspecting() {
			callback("Inspecting project…")
		}

		nonisolated func didStartBuilding(scheme: String) {
			callback("Building \(scheme)…")
		}

		nonisolated func didStartIndexing() {
			callback("Indexing…")
		}

		nonisolated func didStartAnalyzing() {
			callback("Analyzing…")
		}
	}

	// MARK: - Full Configuration API

	/// Run a scan with full Periphery configuration
	/// This API matches ScanCommand.run() functionality
	nonisolated func runScan(
		configuration: Configuration,
		progressHandler: (@Sendable (String) -> Void)? = nil
	) async throws -> ([ScanResult], SourceGraph) {
		progressHandler?("Starting scan…")

		// Run directly in the Task context so Task.checkCancellation() works
		let (result, graph) = try executePeripheryScan(
			configuration: configuration,
			progressHandler: progressHandler
		)

		return (result, graph)
	}

	/// Run a complete scan with progressive streaming of results
	///
	/// This method provides real-time progress updates as the scan executes and
	/// post-processing tasks complete. Results are streamed via AsyncThrowingStream
	/// for progressive UI updates.
	///
	/// **Stream Events:**
	/// 1. `.statusUpdate(String)` - Progress messages during scan
	/// 2. `.scanComplete([ScanResult], SourceGraph)` - Phase 1 complete, tabs can show
	/// 3. `.categoriesSectionAdded(CategoriesNode)` - Each Categories section (7 total)
	///
	/// **Threading:**
	/// - Entire stream runs in Task.detached (off MainActor)
	/// - Categories sections build sequentially
	///
	/// **Cancellation:**
	/// - Stream supports cancellation via Task cancellation
	/// - Cancellation propagates to all sub-tasks
	///
	/// - Parameters:
	///	  - configuration: Periphery configuration
	///	  - projectPath: Optional project path for building results tree
	///	  - projectType: Type of project (xcode or swiftPackage)
	///	  - projectDirectory: Directory containing the project (for SPM, directory containing Package.swift)
	/// - Returns: AsyncThrowingStream of ScanProgress events
	nonisolated func runFullScanWithStreaming(
		configuration: Configuration,
		projectPath: String?,
		projectType: ProjectType,
		projectDirectory: String?
	) -> AsyncThrowingStream<ScanProgress, Error> {
		AsyncThrowingStream { continuation in
			// Calculate project root path (parent directory of .xcodeproj)
			let projectRootPath: String? = if let path = projectPath {
				(path as NSString).deletingLastPathComponent
			} else {
				nil
			}

			let task = Task.detached(priority: .userInitiated) {
				do {
					// For SPM projects, change working directory before scanning
					let originalDirectory = FileManager.default.currentDirectoryPath
					var shouldRestoreDirectory = false

					if projectType == .swiftPackage, let projectDir = projectDirectory {
						FileManager.default.changeCurrentDirectoryPath(projectDir)
						shouldRestoreDirectory = true
					}

					defer {
						if shouldRestoreDirectory {
							FileManager.default.changeCurrentDirectoryPath(originalDirectory)
						}
					}

					// Phase 1: Run scan with progress updates
					let (results, sourceGraph) = try await self.runScan(
						configuration: configuration,
						progressHandler: { status in
							continuation.yield(.statusUpdate(status))
						}
					)

					// Yield Phase 1 completion - UI can show tabs now
					continuation.yield(.scanComplete(results, sourceGraph))
					continuation.yield(.statusUpdate("Processing results…"))

					// Phase 2: Post-processing with streaming
					// Categories: Sequential streaming (7 sections)
					let categoriesTask = Task {
						_ = Dumper()
							.buildCategoriesStreaming(sourceGraph: sourceGraph, projectRootPath: projectRootPath) { section in
								continuation.yield(.categoriesSectionAdded(section))
							}
						if let data = "* ✓ Categories streaming complete\n".data(using: .utf8) {
							try? FileHandle.standardError.write(contentsOf: data)
						}

						/* TODO: Integrate this logic here, roughly:

						 if logToConsole {
						 Task.detached(priority: .utility) {
						 let output = PrintCapture.capture {
						 dumper.printHighLevelTypesAndReferences(sourceGraph: sourceGraph)
						 }
						 "=== Categories Output ===\n\(output)".logToConsole()
						 }
						 }
						 */
					}

					// Wait for both tasks to complete
					_ = await categoriesTask.value

					// Stream complete
					if let data = "* ✓ All post-processing complete\n".data(using: .utf8) {
						try? FileHandle.standardError.write(contentsOf: data)
					}
					continuation.finish()
				} catch {
					continuation.finish(throwing: error)
				}
			}

			continuation.onTermination = { _ in
				task.cancel()
			}
		}
	}

	// MARK: - Core Scan Logic (extracted from ScanCommand.run())

	private nonisolated func executePeripheryScan(
		configuration: Configuration,
		progressHandler: (@Sendable (String) -> Void)?
	) throws -> ([ScanResult], SourceGraph) {
		// Create progress delegate if handler provided
		let progressDelegate = progressHandler.map { ProgressBridge(callback: $0) }

		// Build filename matchers (required for filtering)
		// Manually build them since buildFilenameMatchers() has accessibility issues
		let pwd = FilePath.current.string
		configuration.indexExcludeMatchers = configuration.indexExclude.map {
			FilenameMatcher(relativePattern: $0, to: pwd, caseSensitive: false)
		}
		configuration.retainFilesMatchers = configuration.retainFiles.map {
			FilenameMatcher(relativePattern: $0, to: pwd, caseSensitive: false)
		}
		configuration.reportExcludeMatchers = configuration.reportExclude.map {
			FilenameMatcher(relativePattern: $0, to: pwd, caseSensitive: false)
		}
		configuration.reportIncludeMatchers = configuration.reportInclude.map {
			FilenameMatcher(relativePattern: $0, to: pwd, caseSensitive: false)
		}

		// Create logger with configuration settings
		let logger = Logger(
			quiet: configuration.quiet,
			verbose: configuration.verbose, colorMode: .never
		)

		// Use custom shell that sets up PATH for GUI apps
		let shell = GUIShell(logger: logger)

		// Validate Swift version
		let swiftVersion = SwiftVersion(shell: shell)
		try swiftVersion.validateVersion()

		// Swift 6.1 workaround (from ScanCommand.run():216-219)
		if swiftVersion.version.isVersion(equalTo: "6.1"), !configuration.retainAssignOnlyProperties {
			logger
				.warn(
					"Assign-only property analysis is disabled with Swift 6.1 due to a Swift bug: https://github.com/swiftlang/swift/issues/80394."
				)
			configuration.retainAssignOnlyProperties = true
		}

		// Create project
		let project = try Project(
			configuration: configuration,
			shell: shell,
			logger: logger,
			progressDelegate: progressDelegate
		)

		// Perform scan
		let (results, graph) = try Scan(
			configuration: configuration,
			logger: logger,
			swiftVersion: swiftVersion,
			progressDelegate: progressDelegate
		).perform(project: project)

		// Load baseline if specified (from ScanCommand.run():237-242)
		var baseline: Baseline?
		if let baselinePath = configuration.baseline {
			let data = try Data(contentsOf: baselinePath.url)
			baseline = try JSONDecoder().decode(Baseline.self, from: data)
		}

		// Filter results with baseline and report filters (from ScanCommand.run():244)
		let filteredResults = try OutputDeclarationFilter(
			configuration: configuration,
			logger: logger
		).filter(results, with: baseline)

		// Write baseline if specified (from ScanCommand.run():246-252)
		if let baselinePath = configuration.writeBaseline {
			let usrs = filteredResults
				.flatMapSet { $0.usrs }
				.union(baseline?.usrs ?? [])
			let newBaseline = Baseline.v1(usrs: usrs.sorted())
			let data = try JSONEncoder().encode(newBaseline)
			try data.write(to: baselinePath.url)
		}

		// Write formatted results to file if specified (from ScanCommand.run():265-275)
		if !filteredResults.isEmpty, let resultsPath = configuration.writeResults {
			let outputFormat = configuration.outputFormat
			let formatter = outputFormat.formatter.init(configuration: configuration, logger: logger)

			if let output: String = try formatter.format(filteredResults, colored: false) {
				try output.write(to: resultsPath.url, atomically: true, encoding: .utf8)
			}
		}

		// Throw error in strict mode if issues found (from ScanCommand.run():282-284)
		if !filteredResults.isEmpty, configuration.strict {
			throw PeripheryError.foundIssues(count: filteredResults.count)
		}

		return (filteredResults, graph)
	}
}
