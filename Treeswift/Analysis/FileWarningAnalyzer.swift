//
//  FileWarningAnalyzer.swift
//  Treeswift
//
//  Analyzes individual files for shared code warnings
//

import Foundation
import SourceGraph
import SystemPackage

final class FileWarningAnalyzer: Sendable {
	// Shared analysis context to avoid repeated work per file
	private struct AnalysisContext {
		let declarationsByFile: [String: [Declaration]]
	}

	/* Computes usage badge text for a file based on reference patterns.
	 Priority order:
	 1. "Folder-private" - has same-folder refs but no cross-folder refs (positive/green)
	 2. "Unused file" - has symbols but no references at all (warning)
	 3. "Shared (N folders)" - symbols referenced by multiple folders
	 4. "N files use" - symbols referenced by N files (cross-folder)
	 5. "Single consumer" - only one file references this
	 6. "N symbols" - default fallback
	 Returns tuple of (badgeText, isWarning, isPositive). */
	private nonisolated static func computeUsageBadge(
		statistics: FileStatistics
	) -> (text: String, isWarning: Bool, isPositive: Bool) {
		let hasSymbols = statistics.symbolCount > 0
		let hasCrossFolderRefs = statistics.externalReferenceCount > 0
		let hasSameFolderRefs = statistics.sameFolderFileCount > 0
		let isEntryPoint = statistics.isEntryPoint

		// Case 1: Folder-private (positive indicator of good encapsulation)
		if statistics.isFolderPrivate {
			return ("Folder-private", false, true)
		}

		// Case 2: Unused file (warning - has symbols but no usage at all)
		if hasSymbols, !hasCrossFolderRefs, !hasSameFolderRefs, !isEntryPoint {
			return ("Unused file", true, false)
		}

		// Case 3: Entry point (show as neutral)
		if isEntryPoint {
			return ("Entry point", false, false)
		}

		// Case 4: Shared across multiple folders
		if statistics.folderReferenceCount >= 2 {
			let folderText = "folders"
			return ("Shared (\(statistics.folderReferenceCount) \(folderText))", false, false)
		}

		// Case 5: Multiple cross-folder files
		if statistics.externalFileCount > 1 {
			let fileText = "files use"
			return ("\(statistics.externalFileCount) \(fileText)", false, false)
		}

		// Case 6: Single consumer (cross-folder)
		if statistics.externalFileCount == 1 {
			return ("Single consumer", false, false)
		}

		// Case 7: Fallback - show symbol count
		if statistics.symbolCount == 0 {
			return ("No symbols", false, false)
		}

		let symbolText = statistics.symbolCount == 1 ? "symbol" : "symbols"
		return ("\(statistics.symbolCount) \(symbolText)", false, false)
	}

	nonisolated init() {}

	nonisolated func analyzeFiles(
		nodes: [FileBrowserNode],
		graph: SourceGraph
	) async -> [FileBrowserNode] {
		// Precompute declarations grouped by file to avoid scanning the whole graph per file
		let declarationsByFile: [String: [Declaration]] = {
			var dict: [String: [Declaration]] = [:]
			for decl in graph.allDeclarations {
				let path = decl.location.file.path.string
				dict[path, default: []].append(decl)
			}
			return dict
		}()
		let context = AnalysisContext(declarationsByFile: declarationsByFile)
		return await analyzeFilesRecursive(nodes: nodes, graph: graph, context: context)
	}

	private nonisolated func analyzeFilesRecursive(
		nodes: [FileBrowserNode],
		graph: SourceGraph,
		context: AnalysisContext
	) async -> [FileBrowserNode] {
		var analyzedNodes: [FileBrowserNode] = []

		for node in nodes {
			switch node {
			case let .directory(dir):
				let enrichedChildren = await analyzeFilesRecursive(
					nodes: dir.children,
					graph: graph,
					context: context
				)

				var mutableDir = dir
				mutableDir.children = enrichedChildren

				analyzedNodes.append(.directory(mutableDir))

			case let .file(file):
				var mutableFile = file
				let analysisResult = analyzeFile(file: file, graph: graph, context: context)
				mutableFile.analysisWarnings = analysisResult.warnings
				mutableFile.statistics = analysisResult.statistics

				// Enrich typeInfos with per-symbol reference data
				if let typeInfos = file.typeInfos {
					mutableFile.typeInfos = typeInfos.map { typeInfo in
						let refs = analysisResult.symbolReferences[typeInfo.name] ?? []
						return FileTypeInfo(
							name: typeInfo.name,
							icon: typeInfo.icon,
							matchesFileName: typeInfo.matchesFileName,
							isUnused: typeInfo.isUnused,
							isRedundantPublic: typeInfo.isRedundantPublic,
							isExtension: typeInfo.isExtension,
							referencingFileNames: refs,
							startLine: typeInfo.startLine
						)
					}
				}

				// Compute usage badge only if NO analysis warnings exist
				if analysisResult.warnings.isEmpty, let stats = analysisResult.statistics {
					let (badgeText, isWarning, isPositive) = Self.computeUsageBadge(statistics: stats)
					mutableFile.usageBadge = UsageBadge(text: badgeText, isWarning: isWarning, isPositive: isPositive)
				}

				analyzedNodes.append(.file(mutableFile))
			}
		}

		return analyzedNodes
	}

	private struct FileAnalysisResult {
		let warnings: [AnalysisWarning]
		let statistics: FileStatistics?
		let symbolReferences: [String: [String]] // symbol name -> referencing file names
	}

	private nonisolated func analyzeFile(
		file: FileBrowserFile,
		graph: SourceGraph,
		context: AnalysisContext
	) -> FileAnalysisResult {
		// Get all symbols declared in this file from precomputed context
		let fileSymbols = context.declarationsByFile[file.path] ?? []

		// Commonly used path components (computed once)
		let fileName = (file.path as NSString).lastPathComponent
		let folderPath = (file.path as NSString).deletingLastPathComponent
		let folderName = (folderPath as NSString).lastPathComponent

		// Handle files with no symbols
		if fileSymbols.isEmpty {
			let emptyStats = FileStatistics(
				symbolCount: 0,
				externalReferenceCount: 0,
				externalFileCount: 0,
				folderReferenceCount: 0,
				sameFolderFileCount: 0,
				isEntryPoint: false,
				referencingFolders: [],
				sameFolderFileNames: []
			)
			return FileAnalysisResult(warnings: [], statistics: emptyStats, symbolReferences: [:])
		}

		// Analyze cross-folder references (excludes same-folder refs)
		let crossFolderAnalysis = ReferenceAnalysisUtility.analyzeSymbolReferences(
			symbols: fileSymbols,
			sourcePath: folderPath, // Use folder path so references from same folder are excluded
			graph: graph
		)

		// Analyze all references (excludes only same-file refs)
		let allReferencesAnalysis = ReferenceAnalysisUtility.analyzeSymbolReferences(
			symbols: fileSymbols,
			sourcePath: file.path, // Use file path so only self-references are excluded
			graph: graph
		)

		// Build per-symbol reference map (symbol name -> file names)
		var symbolReferences: [String: [String]] = [:]
		for (declaration, filePaths) in allReferencesAnalysis.symbolReferences {
			if let name = declaration.name {
				let fileNames = filePaths.map { ($0 as NSString).lastPathComponent }
				symbolReferences[name] = fileNames.sorted()
			}
		}

		// Calculate same-folder references: files in allReferences but not in crossFolder
		let allExternalFiles = Set(allReferencesAnalysis.symbolReferences.values.flatMap(\.self))
		let crossFolderFiles = Set(crossFolderAnalysis.symbolReferences.values.flatMap(\.self))
		let sameFolderFiles = allExternalFiles.subtracting(crossFolderFiles)
		let sameFolderFileCount = sameFolderFiles.count
		let sameFolderFileNames = sameFolderFiles
			.map { ($0 as NSString).lastPathComponent }
			.sorted()

		// Extract folder names from cross-folder analysis
		let referencingFolders = crossFolderAnalysis.folderReferenceCounts.keys
			.map { ($0 as NSString).lastPathComponent }
			.sorted()

		// Check if file contains an entry point (@main)
		let isEntryPoint = fileSymbols.contains { DeclarationIconHelper.isMainApp($0) }

		let statistics = FileStatistics(
			symbolCount: fileSymbols.count,
			externalReferenceCount: crossFolderAnalysis.externalFileReferenceCount,
			externalFileCount: crossFolderAnalysis.externalFileReferenceCount,
			folderReferenceCount: crossFolderAnalysis.folderReferenceCounts.count,
			sameFolderFileCount: sameFolderFileCount,
			isEntryPoint: isEntryPoint,
			referencingFolders: referencingFolders,
			sameFolderFileNames: sameFolderFileNames
		)

		// Generate warnings for files with shared code (use cross-folder analysis)
		var warnings = generateSharedCodeWarnings(
			file: file,
			symbols: fileSymbols,
			referenceAnalysis: crossFolderAnalysis
		)

		// Check for file name mismatch (single symbol with different name)
		if let types = file.typeInfos, types.count == 1,
		   let singleType = types.first,
		   !singleType.matchesFileName {
			let fileNameWithoutExtension = (fileName as NSString).deletingPathExtension

			// Check if file follows "SymbolName+Extension.swift" pattern (common for extensions)
			let isExtensionPattern = fileNameWithoutExtension.hasPrefix(singleType.name + "+")

			if !isExtensionPattern {
				let suggestedFileName = "\(singleType.name).swift"

				warnings.append(AnalysisWarning(
					severity: .warning,
					message: "File name '\(fileName)' doesn't match symbol '\(singleType.name)'",
					suggestedActions: [
						.renameFileToMatchSymbol(
							currentPath: file.path,
							currentName: fileName,
							suggestedName: suggestedFileName
						)
					],
					details: [
						"This file contains a single symbol '\(singleType.name)'",
						"The filename should match: \(suggestedFileName)"
					]
				))
			}
		}

		// Check for View naming warnings
		let hasViewSymbol = fileSymbols.contains { DeclarationIconHelper.conformsToView($0) }

		if fileName.hasSuffix("View.swift"), !hasViewSymbol {
			// Check if both file AND folder end with "View" (escalated severity)
			if folderName.hasSuffix("View") {
				warnings.append(AnalysisWarning(
					severity: .warning,
					message: "File and folder name suggest View but no View symbol found",
					suggestedActions: [],
					details: [
						"Both '\(fileName)' and '\(folderName)/' suggest this should contain a View",
						"Consider renaming or adding a View conformance"
					]
				))
			} else {
				// Only file ends with "View" (info level)
				warnings.append(AnalysisWarning(
					severity: .info,
					message: "File name suggests View but no View symbol found",
					suggestedActions: [],
					details: [
						"'\(fileName)' suggests this should contain a View",
						"Consider renaming if not View-related"
					]
				))
			}
		}

		// Check for unused files (symbols not referenced by any other file)
		let hasSymbols = fileSymbols.count > 0
		let hasCrossFolderRefs = crossFolderAnalysis.externalFileReferenceCount > 0
		let hasSameFolderRefs = sameFolderFileCount > 0
		let isUnused = hasSymbols && !hasCrossFolderRefs && !hasSameFolderRefs && !isEntryPoint

		if isUnused {
			warnings.append(AnalysisWarning(
				severity: .warning,
				message: "Unused file: symbols are not referenced by any other file",
				suggestedActions: [
					.moveFileToTrash(
						filePath: file.path,
						fileName: fileName
					)
				],
				details: [
					"This file contains \(fileSymbols.count) symbol(s) that are not used anywhere",
					"Consider moving to trash if truly unused"
				]
			))
		}

		// Check for unnecessarily public symbols (only top-level types)
		let topLevelTypes = fileSymbols.filter { symbol in
			let isTopLevelType = switch symbol.kind {
			case .class, .struct, .enum, .protocol:
				true
			default:
				false
			}

			// Exclude extensions, @main entry points, and nested symbols
			let isExtension = [.extensionClass, .extensionStruct, .extensionEnum, .extensionProtocol]
				.contains(symbol.kind)
			let isMain = DeclarationIconHelper.isMainApp(symbol)
			let isNested = symbol.parent != nil

			return isTopLevelType && !isExtension && !isMain && !isNested
		}

		for symbol in topLevelTypes {
			// Check if symbol is public or internal (not already private/fileprivate)
			let isPublicOrInternal = symbol.accessibility.value == .public ||
				symbol.accessibility.value == .internal

			guard isPublicOrInternal else { continue }

			// Check if symbol has any external references (from other files)
			let hasExternalReferences = allReferencesAnalysis.symbolReferences[symbol]?.isEmpty == false

			if !hasExternalReferences {
				// Skip preview symbols (compiler-generated preview infrastructure)
				if symbol.isPreviewSymbol {
					continue
				}

				let symbolName = symbol.name ?? "unknown"
				warnings.append(AnalysisWarning(
					severity: .info,
					message: "\(symbolName) could be private (only used in this file)",
					suggestedActions: [],
					details: [
						"This symbol is not referenced by any other file",
						"Consider making it private or fileprivate to improve encapsulation"
					]
				))
			}
		}

		return FileAnalysisResult(warnings: warnings, statistics: statistics, symbolReferences: symbolReferences)
	}

	private nonisolated func generateSharedCodeWarnings(
		file: FileBrowserFile,
		symbols: [Declaration],
		referenceAnalysis: ReferenceAnalysis
	) -> [AnalysisWarning] {
		var warnings: [AnalysisWarning] = []

		let hasExternalRefs = referenceAnalysis.externalFileReferenceCount > 0
		if hasExternalRefs {
			let symbolDetails = ReferenceAnalysisUtility.buildSymbolReferenceDetails(
				symbols: symbols,
				referenceAnalysis: referenceAnalysis
			)

			let folderCount = referenceAnalysis.folderReferenceCounts.count

			let symbolCount = symbolDetails.consolidatedCount

			let topFolder: (key: String, value: Int)? = referenceAnalysis.folderReferenceCounts
				.max(by: { $0.value < $1.value })

			// Use manual pluralization (same pattern as folder warnings)
			let fileCount = referenceAnalysis.externalFileReferenceCount
			let fileText = fileCount == 1 ? "file" : "files"
			let folderText = folderCount == 1 ? "folder" : "folders"

			var actions: [SuggestedAction] = []

			// If symbols are only used by one folder, suggest moving file to that folder
			if folderCount == 1, let (targetFolderPath, _) = topFolder {
				let sourceFolderPath = (file.path as NSString).deletingLastPathComponent
				let targetFolderName = (targetFolderPath as NSString).lastPathComponent

				// Don't suggest moving to enclosing/ancestor folder - being in a subfolder is fine
				let isAncestor = ReferenceAnalysisUtility.isTargetFolderAncestorOfSource(
					targetFolder: targetFolderPath, sourceFolder: sourceFolderPath
				)

				// Don't suggest moving non-view files into view/UI folders
				let isTargetUIFolder = ReferenceAnalysisUtility.isUIOrViewFolder(folderName: targetFolderName)
				let fileContainsViews = ReferenceAnalysisUtility.containsViewSymbols(symbols)
				let inappropriateForUIFolder = isTargetUIFolder && !fileContainsViews

				if !isAncestor, !inappropriateForUIFolder {
					let fileName = (file.path as NSString).lastPathComponent
					actions.append(.moveFileToFolder(
						filePath: file.path,
						fileName: fileName,
						targetFolder: FolderTarget(folderPath: targetFolderPath, folderName: targetFolderName)
					))
				}
			}

			// Determine badge message based on specific case
			let message: String
			if symbolCount == 1, folderCount == 1, !actions.isEmpty {
				let targetFolderName = (topFolder!.key as NSString).lastPathComponent
				message = "Move to \(targetFolderName)/"
			} else {
				message = "Used by \(fileCount) \(fileText) in \(folderCount) \(folderText)"
			}

			warnings.append(AnalysisWarning(
				severity: .info,
				message: message,
				suggestedActions: actions
			))
		}

		return warnings
	}
}
