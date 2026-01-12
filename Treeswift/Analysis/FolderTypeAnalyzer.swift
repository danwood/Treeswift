//
//  FolderTypeAnalyzer.swift
//  Treeswift
//
//  Analyzes folder structure to classify folders as shared, symbol, or ambiguous
//

import Foundation
import SourceGraph
import SystemPackage

final class FolderTypeAnalyzer: Sendable {

	nonisolated init() {}

	nonisolated func analyzeFolders(
		nodes: [FileBrowserNode],
		graph: SourceGraph,
		projectPath: String
	) async -> [FileBrowserNode] {
		return await analyzeFoldersRecursive(nodes: nodes, graph: graph, projectPath: projectPath)
	}

	private nonisolated func analyzeFoldersRecursive(
		nodes: [FileBrowserNode],
		graph: SourceGraph,
		projectPath: String
	) async -> [FileBrowserNode] {
		var results: [FileBrowserNode?] = Array(repeating: nil, count: nodes.count)

		await withTaskGroup(of: (Int, FileBrowserNode).self) { group in
			for (index, node) in nodes.enumerated() {
				group.addTask { [graph] in
					switch node {
					case .directory(let dir):
						let enrichedChildren = await self.analyzeFoldersRecursive(
							nodes: dir.children,
							graph: graph,
							projectPath: projectPath
						)

						var mutableDir = dir
						mutableDir.children = enrichedChildren

						let analysis = self.analyzeFolder(
							directory: mutableDir,
							graph: graph
						)
						mutableDir.folderType = analysis.folderType
						mutableDir.analysisWarnings = analysis.warnings
						mutableDir.statistics = analysis.statistics

						// Cache whether this directory has folder-private files
						mutableDir.hasFolderPrivateFiles = enrichedChildren.contains { child in
							if case .file(let file) = child {
								return file.statistics?.isFolderPrivate == true
							}
							return false
						}

						// Cache whether this directory contains any .swift files recursively
						mutableDir.containsSwiftFiles = self.directoryContainsSwiftFiles(mutableDir)

						// If this is a shared folder with symbol warnings, attach them to individual files
						if let symbolWarnings = analysis.symbolWarnings, !symbolWarnings.isEmpty {
							mutableDir.children = self.attachSymbolWarningsToFiles(
								children: mutableDir.children,
								symbolWarnings: symbolWarnings
							)
						}

						return (index, FileBrowserNode.directory(mutableDir))

					case .file(let file):
						return (index, FileBrowserNode.file(file))
					}
				}
			}

			for await (index, node) in group {
				results[index] = node
			}
		}

		return results.compactMap { $0 }
	}

	/* Attaches symbol-level warnings to files that contain those symbols.
	   Used for shared folders where individual symbols have warnings but we want to display them
	   on the file level rather than cluttering the folder with many badges. */
	private nonisolated func attachSymbolWarningsToFiles(
		children: [FileBrowserNode],
		symbolWarnings: [Declaration: AnalysisWarning]
	) -> [FileBrowserNode] {
		return children.map { child in
			switch child {
			case .file(var file):
				// Find warnings for symbols in this file
				let fileWarnings = symbolWarnings.filter { (symbol, _) in
					symbol.location.file.path.string == file.path
				}

				// Append symbol warnings to file's existing warnings
				if !fileWarnings.isEmpty {
					var updatedWarnings = file.analysisWarnings
					for (_, warning) in fileWarnings {
						updatedWarnings.append(warning)
					}
					file.analysisWarnings = updatedWarnings
				}

				return .file(file)

			case .directory(let dir):
				// Don't recurse into subdirectories - symbol warnings only apply to direct children
				return .directory(dir)
			}
		}
	}

	private nonisolated func analyzeFolder(
		directory: FileBrowserDirectory,
		graph: SourceGraph
	) -> (folderType: FolderType, warnings: [AnalysisWarning], statistics: FolderStatistics?, symbolWarnings: [Declaration: AnalysisWarning]?) {
		let allDeclarations = graph.allDeclarations

		let swiftFiles = collectSwiftFiles(in: directory)
		guard !swiftFiles.isEmpty else {
			return (.ambiguous, [], nil, nil)
		}

		let folderPath = directory.id
		let folderName = directory.name

		let internalSymbols = findInternalSymbols(
			in: swiftFiles,
			allDeclarations: allDeclarations
		)

		guard !internalSymbols.isEmpty else {
			return (.ambiguous, [], nil, nil)
		}

		let referenceAnalysis = analyzeReferences(
			symbols: internalSymbols,
			folderPath: folderPath,
			graph: graph
		)

		let statistics = FolderStatistics(
			fileCount: swiftFiles.count,
			internalSymbolCount: internalSymbols.count,
			externalReferenceCount: referenceAnalysis.externalFileReferenceCount
		)

		if let symbolFolderResult = tryClassifyAsSymbolFolder(
			folderName: folderName,
			swiftFiles: swiftFiles,
			internalSymbols: internalSymbols,
			referenceAnalysis: referenceAnalysis
		) {
			return (symbolFolderResult.folderType, symbolFolderResult.warnings, statistics, nil)
		}

		if let UIFolderResult = tryClassifyAsUIFolder(
			folderName: folderName
		) {
			return (UIFolderResult.folderType, UIFolderResult.warnings, statistics, UIFolderResult.symbolWarnings)
		}

		if let sharedFolderResult = tryClassifyAsSharedFolder(
			folderName: folderName,
			internalSymbols: internalSymbols,
			referenceAnalysis: referenceAnalysis
		) {
			return (sharedFolderResult.folderType, sharedFolderResult.warnings, statistics, sharedFolderResult.symbolWarnings)
		}

		let warnings = generateAmbiguousWarnings(
			folderName: folderName,
			internalSymbols: internalSymbols,
			referenceAnalysis: referenceAnalysis,
			swiftFiles: swiftFiles
		)

		return (.ambiguous, warnings, statistics, nil)
	}

	private nonisolated func collectSwiftFiles(in directory: FileBrowserDirectory) -> [FileBrowserFile] {
		var files: [FileBrowserFile] = []

		func collectRecursive(nodes: [FileBrowserNode]) {
			for node in nodes {
				switch node {
				case .file(let file):
					files.append(file)
				case .directory(let dir):
					collectRecursive(nodes: dir.children)
				}
			}
		}

		collectRecursive(nodes: directory.children)
		return files
	}

	private nonisolated func findInternalSymbols(
		in files: [FileBrowserFile],
		allDeclarations: Set<Declaration>
	) -> [Declaration] {
		let filePaths = Set(files.map { $0.path })

		var symbols: [Declaration] = []
		for decl in allDeclarations {
			let loc = decl.location
			if filePaths.contains(loc.file.path.string) {
				symbols.append(decl)
			}
		}

		return symbols
	}

	private nonisolated func analyzeReferences(
		symbols: [Declaration],
		folderPath: String,
		graph: SourceGraph
	) -> ReferenceAnalysis {
		return ReferenceAnalysisUtility.analyzeSymbolReferences(symbols: symbols, sourcePath: folderPath, graph: graph)
	}

	// If possible, classify as symbol folder or its more specialized view folder
	private nonisolated func tryClassifyAsSymbolFolder(
		folderName: String,
		swiftFiles: [FileBrowserFile],
		internalSymbols: [Declaration],
		referenceAnalysis: ReferenceAnalysis
	) -> (folderType: FolderType, warnings: [AnalysisWarning])? {

		// auto-detection (folder name matches file and symbol)
		let expectedFileName = folderName + ".swift"
		guard let mainFile = swiftFiles.first(where: { $0.name == expectedFileName }) else {
			return nil
		}

		guard let mainSymbol: Declaration = internalSymbols.first(where: {
			let loc = $0.location
			return loc.file.path.string == mainFile.path && $0.name == folderName
		}) else {
			return nil
		}

		let folderType: FolderType
		let symbolIcon = DeclarationIconHelper.typeIcon(for: mainSymbol)
		if DeclarationIconHelper.conformsToView(mainSymbol) {
			folderType = .view(mainSymbolName: folderName, icon: symbolIcon)
		} else {
			folderType = .symbol(mainSymbolName: folderName, icon: symbolIcon)
		}

		return classifyWithMainSymbol(
			mainSymbol: mainSymbol,
			mainSymbolName: folderName,
			folderType: folderType,
			internalSymbols: internalSymbols,
			referenceAnalysis: referenceAnalysis,
			swiftFiles: swiftFiles
		)
	}

	private nonisolated func classifyWithMainSymbol(
		mainSymbol: Declaration,
		mainSymbolName: String,
		folderType: FolderType,
		internalSymbols: [Declaration],
		referenceAnalysis: ReferenceAnalysis,
		swiftFiles: [FileBrowserFile]
	) -> (folderType: FolderType, warnings: [AnalysisWarning])? {

		let otherSymbols = internalSymbols.filter { $0 != mainSymbol }
		var warnings: [AnalysisWarning] = []

		/* Filter out symbols that are legitimately part of the main symbol's public API.
		   Direct members (children) of the main symbol with public/internal accessibility
		   are expected to be used externally when the main symbol is used. */
		let mainSymbolMembers = otherSymbols.filter { symbol in
			// Check if this symbol's parent is the main symbol
			guard let parent = symbol.parent else { return false }
			if parent != mainSymbol { return false }

			// Only consider public/internal members as part of the API
			let accessibility = symbol.accessibility.value
			return accessibility == .public || accessibility == .internal
		}

		/* Leaked symbols are those referenced externally, excluding:
		   1. The main symbol itself (already filtered in otherSymbols)
		   2. Direct members of the main symbol (part of its public API) */
		let leakedSymbols = otherSymbols.filter { symbol in
			// Must be referenced externally
			guard referenceAnalysis.symbolsWithExternalReferences.contains(symbol) else { return false }

			// Exclude main symbol's public/internal members
			return !mainSymbolMembers.contains(symbol)
		}

		if !leakedSymbols.isEmpty {
			let symbolNames = leakedSymbols.compactMap { $0.name }.sorted().joined(separator: ", ")

			var details: [String] = []
			details.append("Leaked support symbols (\(leakedSymbols.count)):")
			for symbol in leakedSymbols.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
				let symbolName = symbol.name ?? "unknown"
				let refFiles = referenceAnalysis.symbolReferences[symbol] ?? []
				let refFolders = Set(refFiles.map { ReferenceAnalysisUtility.extractFolderPath(from: $0) })
				details.append("• \(symbolName) → \(refFolders.count) folders, \(refFiles.count) files")
			}

			let symbolsToMove = leakedSymbols.map { symbol in
				return symbol.name ?? "unknown"
			}

			let actions: [SuggestedAction] = [
				.moveSymbolsToFolder(
					symbols: symbolsToMove,
					targetFolder: FolderTarget(
						folderPath: "",
						folderName: "Shared"
					)
				),
				.refactorToUseMainSymbol(
					folderPath: swiftFiles.first?.path.replacingOccurrences(of: "/\(swiftFiles.first?.name ?? "")", with: "") ?? "",
					mainSymbol: mainSymbolName,
					leakedSymbols: leakedSymbols.compactMap { $0.name }
				)
			]

			var symbolRefs: [SymbolReference] = []

			symbolRefs.append(SymbolReference(
				symbolName: mainSymbol.name ?? "unknown",
				icon: mainSymbol.kind.icon,
				filePath: mainSymbol.location.file.path.string,
				line: mainSymbol.location.line,
				shouldBePublic: true
			))

			for symbol in leakedSymbols.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
				symbolRefs.append(SymbolReference(
					symbolName: symbol.name ?? "unknown",
					icon: symbol.kind.icon,
					filePath: symbol.location.file.path.string,
					line: symbol.location.line,
					shouldBePublic: false
				))
			}

			warnings.append(AnalysisWarning(
				severity: .warning,
				message: "Support symbols leaked: \(symbolNames)",
				suggestedActions: actions,
				details: details,
				symbolReferences: symbolRefs
			))
			return nil
		}

		

		if swiftFiles.count > 10 {
			let folderPath = swiftFiles.first?.path.replacingOccurrences(of: "/\(swiftFiles.first?.name ?? "")", with: "") ?? ""

			warnings.append(AnalysisWarning(
				severity: .info,
				message: "Folder is complex (\(swiftFiles.count) files)",
				suggestedActions: [
					.splitFolderIntoSubfolders(
						folderPath: folderPath,
						suggestion: "Extract related symbols into subfolders"
					)
				]
			))
		}

		return (folderType, warnings)
	}

	private nonisolated func tryClassifyAsUIFolder(
		folderName: String
	) -> (folderType: FolderType, warnings: [AnalysisWarning], symbolWarnings: [Declaration: AnalysisWarning])? {

		let uiKeywords = ["ui", "views", "interface"]
		let isNamedLikeUI = uiKeywords.contains { folderName.lowercased().contains($0) }

		guard isNamedLikeUI else {
			return nil
		}
		return (.ui, [], [:])
	}

	private nonisolated func tryClassifyAsSharedFolder(
		folderName: String,
		internalSymbols: [Declaration],
		referenceAnalysis: ReferenceAnalysis
	) -> (folderType: FolderType, warnings: [AnalysisWarning], symbolWarnings: [Declaration: AnalysisWarning])? {
		/* Folders with these names are classified as "shared folders" and held to stricter standards.
		   Philosophy: Code in Utilities/Helpers/Shared folders should be widely reused across the codebase.
		   If a symbol is only used in one place, it should live closer to where it's used, not in a shared folder.
		   This prevents shared folders from becoming dumping grounds for single-purpose code. */
		let sharedKeywords = ["shared", "common", "extension", "support", "utilit", "helper"]
		let isNamedLikeShared = sharedKeywords.contains { folderName.lowercased().contains($0) }

		guard isNamedLikeShared else {
			return nil
		}

		var symbolWarnings: [Declaration: AnalysisWarning] = [:]

		for symbol in internalSymbols {
			let referencingFiles = referenceAnalysis.symbolReferences[symbol] ?? []
			let refCount = referencingFiles.count

			/* Orange WARNING (not just info): Symbol in shared folder used by only one file.
			   Shared folders should contain widely-reused utilities. Single-use code should live
			   in the folder where it's used, not in a "shared" folder. Suggest moving the symbol. */
			if refCount == 1 {
				let symbolName = symbol.name ?? "unknown"
				let filePath = referencingFiles.first!
				let fileName = (filePath as NSString).lastPathComponent
				let targetFolderPath = ReferenceAnalysisUtility.extractFolderPath(from: filePath)
				let targetFolderName = (targetFolderPath as NSString).lastPathComponent

				let details = [
					"Referenced from:",
					"• \(fileName)",
					"",
					"Location: \(targetFolderName)/"
				]

				let currentFilePath = symbol.location.file.path.string
				let sourceFolderPath = ReferenceAnalysisUtility.extractFolderPath(from: currentFilePath)

				// Don't suggest moving to enclosing/ancestor folder
				let isAncestor = ReferenceAnalysisUtility.isTargetFolderAncestorOfSource(
					targetFolder: targetFolderPath, sourceFolder: sourceFolderPath
				)

				// Don't suggest moving non-view symbols into view/UI folders
				let isTargetUIFolder = ReferenceAnalysisUtility.isUIOrViewFolder(folderName: targetFolderName)
				let symbolIsView = DeclarationIconHelper.conformsToView(symbol)
				let inappropriateForUIFolder = isTargetUIFolder && !symbolIsView

				var actions: [SuggestedAction] = []
				if !isAncestor && !inappropriateForUIFolder {
					actions.append(.moveSymbolsToFolder(
						symbols: [symbolName],
						targetFolder: FolderTarget(
							folderPath: targetFolderPath,
							folderName: targetFolderName
						)
					))
				}

				symbolWarnings[symbol] = AnalysisWarning(
					severity: .warning,
					message: "\(symbolName) only referenced from \(fileName)",
					suggestedActions: actions,
					details: details
				)
			} else if refCount > 1 {
				let folders = Set(referencingFiles.map { ReferenceAnalysisUtility.extractFolderPath(from: $0) })
				/* Orange WARNING: Symbol used by multiple files, but all in the same folder.
				   Even with multiple consumers, if they're all in one folder, the symbol belongs there.
				   This reinforces the shared folder philosophy: only truly cross-cutting utilities belong here. */
				if folders.count == 1 {
					let symbolName = symbol.name ?? "unknown"
					let targetFolderPath = folders.first!
					let targetFolderName = (targetFolderPath as NSString).lastPathComponent

					var details: [String] = []
					details.append("Referenced from \(refCount) files in \(targetFolderName)/:")
					for filePath in referencingFiles.sorted() {
						let fileName = (filePath as NSString).lastPathComponent
						details.append("• \(fileName)")
					}

					let currentFilePath = symbol.location.file.path.string
					let sourceFolderPath = ReferenceAnalysisUtility.extractFolderPath(from: currentFilePath)

					// Don't suggest moving to enclosing/ancestor folder
					let isAncestor = ReferenceAnalysisUtility.isTargetFolderAncestorOfSource(
						targetFolder: targetFolderPath, sourceFolder: sourceFolderPath
					)

					// Don't suggest moving non-view symbols into view/UI folders
					let isTargetUIFolder = ReferenceAnalysisUtility.isUIOrViewFolder(folderName: targetFolderName)
					let symbolIsView = DeclarationIconHelper.conformsToView(symbol)
					let inappropriateForUIFolder = isTargetUIFolder && !symbolIsView

					var actions: [SuggestedAction] = []
					if !isAncestor && !inappropriateForUIFolder {
						actions.append(.moveSymbolsToFolder(
							symbols: [symbolName],
							targetFolder: FolderTarget(
								folderPath: targetFolderPath,
								folderName: targetFolderName
							)
						))
					}

					symbolWarnings[symbol] = AnalysisWarning(
						severity: .warning,
						message: "\(symbolName) only used in \(targetFolderName)/ (\(refCount) files)",
						suggestedActions: actions,
						details: details
					)
				}
			}
		}

		// Create summary warning for folder
		var folderWarnings: [AnalysisWarning] = []
		if !symbolWarnings.isEmpty {
			let count = symbolWarnings.count
			let symbolText = count == 1 ? "symbol" : "symbols"
			folderWarnings.append(AnalysisWarning(
				severity: .warning,
				message: "\(count) single-use \(symbolText)",
				suggestedActions: [],
				details: ["This folder contains \(count) \(symbolText) that should be moved to where they're used."]
			))
		}

		return (.shared(symbolCount: internalSymbols.count), folderWarnings, symbolWarnings)
	}

	private nonisolated func generateAmbiguousWarnings(
		folderName: String,
		internalSymbols: [Declaration],
		referenceAnalysis: ReferenceAnalysis,
		swiftFiles: [FileBrowserFile]
	) -> [AnalysisWarning] {
		var warnings: [AnalysisWarning] = []

		let expectedFileName = folderName + ".swift"
		if swiftFiles.contains(where: { $0.name == expectedFileName }) {
			/* This warning fires when a folder has a main file matching its name but failed
			   to classify as a symbol folder. The most common reason is that support symbols
			   within the folder are referenced externally (leaked), preventing proper encapsulation. */
			let folderPath = swiftFiles.first?.path.replacingOccurrences(of: "/\(swiftFiles.first?.name ?? "")", with: "") ?? ""

			let mainSymbol = internalSymbols.first { $0.name == folderName }
			let leakedSymbols = internalSymbols.filter {
				referenceAnalysis.symbolsWithExternalReferences.contains($0) && $0 != mainSymbol
			}

			var symbolRefs: [SymbolReference] = []
			if let mainSymbol = mainSymbol {
				symbolRefs.append(SymbolReference(
					symbolName: mainSymbol.name ?? "unknown",
					icon: mainSymbol.kind.icon,
					filePath: mainSymbol.location.file.path.string,
					line: mainSymbol.location.line,
					shouldBePublic: true
				))
			}

			for symbol in leakedSymbols.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
				symbolRefs.append(SymbolReference(
					symbolName: symbol.name ?? "unknown",
					icon: symbol.kind.icon,
					filePath: symbol.location.file.path.string,
					line: symbol.location.line,
					shouldBePublic: false
				))
			}

			warnings.append(AnalysisWarning(
				severity: .info,
				message: "Has main file '\(expectedFileName)' but support symbols leak externally",
				suggestedActions: [
					.checkEncapsulation(
						folderPath: folderPath,
						reason: "Some support symbols are referenced from outside this folder"
					)
				],
				symbolReferences: symbolRefs.isEmpty ? nil : symbolRefs
			))
		}

		let hasMultipleExternalRefs = referenceAnalysis.externalFileReferenceCount > 1
		if hasMultipleExternalRefs {
			let symbolsWithRefs = internalSymbols.filter {
				referenceAnalysis.symbolsWithExternalReferences.contains($0)
			}

			let folderCount = referenceAnalysis.folderReferenceCounts.count

			var details: [String] = []

			let symbolDetails = ReferenceAnalysisUtility.buildSymbolReferenceDetails(symbols: symbolsWithRefs, referenceAnalysis: referenceAnalysis)
			let symbolCount = symbolDetails.consolidatedCount

			details.append("Shared symbols (\(symbolCount)):")
			details.append(contentsOf: symbolDetails.details)

			details.append("")
			details.append("Referenced from folders:")
			let sortedFolders = referenceAnalysis.folderReferenceCounts
				.sorted { $0.value > $1.value }
			for (folderPath, _) in sortedFolders {
				let targetFolderName = (folderPath as NSString).lastPathComponent
				let files = referenceAnalysis.folderReferenceFiles[folderPath] ?? []
				let fileCount = files.count

				if fileCount == 1, let fileName = files.first.map({ ($0 as NSString).lastPathComponent }) {
					details.append("• \(targetFolderName)/\(fileName)")
				} else if fileCount == 2 {
					let fileNames = files.sorted().map { ($0 as NSString).lastPathComponent }
					let fileList = fileNames.joined(separator: ", ")
					details.append("• \(targetFolderName)/ (\(fileList))")
				} else {
					details.append("• \(targetFolderName)/ (\(fileCount) files)")
				}
			}

			let currentPath = swiftFiles.first?.path.replacingOccurrences(of: "/\(swiftFiles.first?.name ?? "")", with: "") ?? ""

			// Note: Cannot use inflection syntax ^[symbol](inflect: true) here because:
			// 1. Inflection only works with string literals, not dynamically constructed strings
			// 2. AnalysisWarning.message is String (not LocalizedStringKey) for Hashable conformance
			// 3. AnalysisWarningBadge concatenates the message with other strings
			let fileCount = referenceAnalysis.externalFileReferenceCount
			let fileText = fileCount == 1 ? "file" : "files"
			let folderText = folderCount == 1 ? "folder" : "folders"

			var actions: [SuggestedAction] = [
				.renameFolder(
					currentPath: currentPath,
					suggestedName: "Shared \(folderName)"
				)
			]

			// If shared code is only used by one folder, suggest moving this folder into it
			if folderCount == 1, let (targetFolderPath, _) = sortedFolders.first {
				let targetFolderName = (targetFolderPath as NSString).lastPathComponent

				// Don't suggest moving to enclosing/ancestor folder
				let isAncestor = ReferenceAnalysisUtility.isTargetFolderAncestorOfSource(
					targetFolder: targetFolderPath, sourceFolder: currentPath
				)

				// Don't suggest moving non-view folders into view/UI folders
				let isTargetUIFolder = ReferenceAnalysisUtility.isUIOrViewFolder(folderName: targetFolderName)
				let folderContainsViews = ReferenceAnalysisUtility.containsViewSymbols(internalSymbols)
				let inappropriateForUIFolder = isTargetUIFolder && !folderContainsViews

				if !isAncestor && !inappropriateForUIFolder {
					actions.append(.moveFolderIntoFolder(
						sourceFolderPath: currentPath,
						sourceFolderName: folderName,
						targetFolder: FolderTarget(folderPath: targetFolderPath, folderName: targetFolderName)
					))
				}
			}

			warnings.append(AnalysisWarning(
				severity: .info,
				message: "Used by \(fileCount) \(fileText) in \(folderCount) \(folderText)",
				suggestedActions: actions,
				details: details
			))
		}

		return warnings
	}

	private nonisolated func directoryContainsSwiftFiles(_ directory: FileBrowserDirectory) -> Bool {
		for child in directory.children {
			switch child {
			case .file:
				return true  // Any file means Swift file (scanner only includes .swift)
			case .directory(let subdir):
				if directoryContainsSwiftFiles(subdir) {
					return true
				}
			}
		}
		return false
	}
}
