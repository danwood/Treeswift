//
//  FileTypeAnalyzer.swift
//  Treeswift
//
//  Analyzes Swift files to extract type information from SourceGraph
//

import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

final class FileTypeAnalyzer: Sendable {
	nonisolated init() {}

	nonisolated func enrichFilesWithTypeInfo(
		fileNodes: [FileBrowserNode],
		graph: SourceGraph,
		scanResults: [ScanResult]
	) async -> [FileBrowserNode] {
		// Build warning cache once for all files
		let warningCache = TypeWarningCache.buildCache(from: scanResults)

		// We will process directories recursively (depth-first), but analyze files at each level concurrently.
		var enrichedNodes = fileNodes // start from original to preserve ordering and enable in-place replacement

		// First, collect indices of directories and files at this level
		var directoryIndices: [Int] = []
		var fileWorkItems: [(index: Int, path: String)] = []
		for (idx, node) in fileNodes.enumerated() {
			switch node {
			case .directory:
				directoryIndices.append(idx)
			case let .file(file):
				fileWorkItems.append((index: idx, path: file.path))
			}
		}

		// Analyze files concurrently and store results by index
		var analyzedByIndex: [Int: [FileTypeInfo]] = [:]
		await withTaskGroup(of: (Int, [FileTypeInfo]).self) { group in
			for item in fileWorkItems {
				group.addTask {
					let typeInfos = await self.analyzeFile(path: item.path, graph: graph, warningCache: warningCache)
					return (item.index, typeInfos)
				}
			}
			for await (idx, typeInfos) in group {
				analyzedByIndex[idx] = typeInfos
			}
		}

		// Apply analyzed results to files in-place, preserving order
		for (idx, node) in enrichedNodes.enumerated() {
			guard case var .file(file) = node else { continue }
			if let typeInfos = analyzedByIndex[idx] {
				file.typeInfos = typeInfos.isEmpty ? nil : typeInfos
				enrichedNodes[idx] = .file(file)
			}
		}

		// Recurse into directories (sequentially to avoid excessive parallelism and preserve structure)
		for idx in directoryIndices {
			if case var .directory(dir) = enrichedNodes[idx] {
				let enrichedChildren = await enrichFilesWithTypeInfo(
					fileNodes: dir.children,
					graph: graph,
					scanResults: scanResults
				)
				dir.children = enrichedChildren
				enrichedNodes[idx] = .directory(dir)
			}
		}

		return enrichedNodes
	}

	private nonisolated func analyzeFile(
		path: String,
		graph: SourceGraph,
		warningCache: [TypeWarningKey: TypeWarningStatus]
	) async -> [FileTypeInfo] {
		let allDeclarations = graph.allDeclarations

		/* All top-level symbol kinds we track - includes types, typealiases, free functions,
		 global variables, operators, precedence groups, and macros. */
		let topLevelSymbolKinds: Set<Declaration.Kind> = [
			.class,
			.struct,
			.enum,
			.protocol,
			.extension,
			.extensionClass,
			.extensionEnum,
			.extensionStruct,
			.extensionProtocol,
			.typealias,
			.functionFree,
			.varGlobal,
			.functionOperator,
			.functionOperatorInfix,
			.functionOperatorPostfix,
			.functionOperatorPrefix,
			.precedenceGroup,
			.macro
		]

		let targetPath = path
		let fileDeclarations = allDeclarations.filter { $0.location.file.path.string == targetPath }

		/* Filter for top-level symbols that are accessible across files.
		 We exclude private/fileprivate (file/scope-scoped) but include everything else
		 (internal, public, open, package). For folder organization analysis, internal and
		 public are treated equivalently - both can be referenced across files within the module. */
		var allTopLevelSymbols: [Declaration] = []
		for decl in fileDeclarations {
			if topLevelSymbolKinds.contains(decl.kind),
			   decl.isAccessibleAcrossFiles,
			   decl.parent == nil {
				allTopLevelSymbols.append(decl)
			}
		}

		/* Check if this is an extension-only file. Extension members (methods, properties) have
		 a parent type that's NOT defined in the same file. */
		var isExtensionOnlyFile = false
		var extensionParentName: String?
		if allTopLevelSymbols.isEmpty, !fileDeclarations.isEmpty {
			// Get all parent types defined in this file (top-level types with no parent)
			let typesDefinedInFile = Set(fileDeclarations.filter {
				$0.parent == nil && $0.kind.isTypeKind && !$0.kind.isExtensionKind
			}.compactMap(\.name))

			// Get all parent names of declarations in this file
			let parentNames = Set(fileDeclarations.compactMap { $0.parent?.name })

			// If there are extension members (parents exist) but none of those parents are defined here
			if !parentNames.isEmpty, parentNames.isDisjoint(with: typesDefinedInFile) {
				isExtensionOnlyFile = true
				extensionParentName = fileDeclarations.first?.parent?.name
			}
		}

		var typeInfos: [FileTypeInfo] = []
		let fileName = (path as NSString).lastPathComponent
		let fileNameWithoutExtension = (fileName as NSString).deletingPathExtension

		/* Build typeInfos from all top-level symbols.
		 Process primary types first, then extensions, then other symbols. This ensures that
		 if @Observable generates both a class and an extension with the same name, the class
		 is processed first and the extension is skipped as a duplicate. */
		var processedSymbolNames = Set<String>()
		let sortedSymbols = allTopLevelSymbols.sorted(by: { getStartLine($0) < getStartLine($1) })
		let primaryTypes = sortedSymbols.filter { $0.kind.isTypeKind && !$0.kind.isExtensionKind }
		let extensionTypes = sortedSymbols.filter(\.kind.isExtensionKind)
		let otherSymbols = sortedSymbols.filter { !$0.kind.isTypeKind && !$0.kind.isExtensionKind }

		for decl in primaryTypes + extensionTypes + otherSymbols {
			// Skip preview symbols (compiler-generated preview infrastructure)
			if decl.isPreviewSymbol {
				continue
			}

			let symbolName = decl.name ?? "unknown"

			// Skip if already processed (handles macro-generated duplicates like @Observable)
			if processedSymbolNames.contains(symbolName) {
				continue
			}

			let icon = DeclarationIconHelper.typeIcon(for: decl).asText

			// Check if symbol name matches file name
			let matchesFileName = symbolName == fileNameWithoutExtension

			// Look up warning status from cache
			let warningKey = TypeWarningKey(typeName: symbolName, filePath: path)
			let warningStatus = warningCache[warningKey] ?? TypeWarningStatus(isUnused: false, isRedundantPublic: false)

			typeInfos.append(FileTypeInfo(
				name: symbolName,
				icon: icon,
				matchesFileName: matchesFileName,
				isUnused: warningStatus.isUnused,
				isRedundantPublic: warningStatus.isRedundantPublic,
				isExtension: decl.kind.isExtensionKind,
				startLine: getStartLine(decl)
			))

			processedSymbolNames.insert(symbolName)
		}

		/* If this is an extension-only file with no typeInfos yet, create a synthetic
		 extension entry so the file shows the 🧩 icon. */
		if isExtensionOnlyFile, typeInfos.isEmpty, let parentName = extensionParentName {
			typeInfos.append(FileTypeInfo(
				name: parentName,
				icon: "🧩",
				matchesFileName: false,
				isUnused: false,
				isRedundantPublic: false,
				isExtension: true
			))
		}

		return typeInfos
	}

	private nonisolated func getStartLine(_ decl: Declaration) -> Int {
		let loc = decl.location
		return loc.line
	}
}

extension Declaration {
	/* Returns true if this declaration is accessible across files within the module.
	 Excludes private and fileprivate, includes internal, public, open, and package.

	 For folder organization analysis, internal and public symbols are treated
	 equivalently - both can be referenced across files within the module. */
	nonisolated var isAccessibleAcrossFiles: Bool {
		accessibility.value != .private && accessibility.value != .fileprivate
	}
}
