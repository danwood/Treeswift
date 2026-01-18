//
//  ReferenceAnalysisUtility.swift
//  Treeswift
//
//  Shared utilities for analyzing symbol references across files and folders
//

import Foundation
import SourceGraph
import SystemPackage

nonisolated struct ReferenceAnalysis {
	let symbolReferences: [Declaration: Set<String>]
	let externalFileReferenceCount: Int
	let symbolsWithExternalReferences: Set<Declaration>
	let folderReferenceCounts: [String: Int]
	let folderReferenceFiles: [String: Set<String>] // folder path -> file paths
}

/// Represents a consolidated reference from a source file to a target container
private nonisolated struct ConsolidatedReference: Hashable, Sendable {
	let sourceFilePath: String
	let targetContainerId: ObjectIdentifier

	nonisolated init(sourceFilePath: String, targetContainer: Declaration) {
		self.sourceFilePath = sourceFilePath
		targetContainerId = ObjectIdentifier(targetContainer)
	}

	nonisolated func hash(into hasher: inout Hasher) {
		hasher.combine(sourceFilePath)
		hasher.combine(targetContainerId)
	}

	nonisolated static func == (lhs: ConsolidatedReference, rhs: ConsolidatedReference) -> Bool {
		lhs.sourceFilePath == rhs.sourceFilePath &&
			lhs.targetContainerId == rhs.targetContainerId
	}
}

nonisolated enum ReferenceAnalysisUtility {
	static func analyzeSymbolReferences(
		symbols: [Declaration],
		sourcePath: String,
		sourceGraph: SourceGraph
	) -> ReferenceAnalysis {
		var symbolReferences: [Declaration: Set<String>] = [:]
		var allExternalFiles: Set<String> = []
		var symbolsWithExternal: Set<Declaration> = []
		var consolidatedRefs: Set<ConsolidatedReference> = []

		for symbol in symbols {
			let refs = sourceGraph.references(to: symbol)
			var referencingFiles: Set<String> = []

			for ref in refs {
				let refLoc = ref.location
				let refFilePath = refLoc.file.path.string
				let declLoc = symbol.location
				let declFilePath = declLoc.file.path.string

				// Check if reference is external (different file and outside source path)
				if refFilePath != declFilePath, !refFilePath.starts(with: sourcePath) {
					referencingFiles.insert(refFilePath)
					allExternalFiles.insert(refFilePath)
					symbolsWithExternal.insert(symbol)

					// Track consolidated reference: (source file, top-level container)
					let container = findTopLevelContainer(for: symbol)
					consolidatedRefs.insert(ConsolidatedReference(
						sourceFilePath: refFilePath,
						targetContainer: container
					))
				}
			}

			symbolReferences[symbol] = referencingFiles
		}

		// Convert consolidated references to folder counts and file lists
		var folderRefCounts: [String: Int] = [:]
		var folderRefFiles: [String: Set<String>] = [:]
		for consolidatedRef in consolidatedRefs {
			let folderPath = extractFolderPath(from: consolidatedRef.sourceFilePath)
			folderRefCounts[folderPath, default: 0] += 1
			folderRefFiles[folderPath, default: []].insert(consolidatedRef.sourceFilePath)
		}

		return ReferenceAnalysis(
			symbolReferences: symbolReferences,
			externalFileReferenceCount: allExternalFiles.count,
			symbolsWithExternalReferences: symbolsWithExternal,
			folderReferenceCounts: folderRefCounts,
			folderReferenceFiles: folderRefFiles
		)
	}

	static func extractFolderPath(from filePath: String) -> String {
		(filePath as NSString).deletingLastPathComponent
	}

	/* Find the top-level container (class, struct, enum, protocol) for a declaration.
	 Walks up the parent chain to find the outermost type container.
	 Extensions are treated as separate containers from their base types. */
	static func findTopLevelContainer(for declaration: Declaration) -> Declaration {
		var current = declaration
		var topContainer = declaration

		while let parent = current.parent {
			// Check if parent is a container type
			let containerKinds: Set<Declaration.Kind> = [
				.class, .struct, .enum, .protocol,
				.extensionClass, .extensionStruct, .extensionEnum, .extensionProtocol
			]

			if containerKinds.contains(parent.kind) {
				topContainer = parent
			}

			current = parent
		}

		return topContainer
	}

	/* Check if target folder is an ancestor of (or same as) the source folder.
	 Used to filter out move suggestions where the file/symbol would move "up" to a parent folder.
	 Being in a subfolder is considered good organization, so we don't suggest moving up. */
	static func isTargetFolderAncestorOfSource(targetFolder: String, sourceFolder: String) -> Bool {
		// Normalize both paths to absolute paths (remove trailing slash for comparison)
		let normalizedTarget = (targetFolder as NSString).standardizingPath
		let normalizedSource = (sourceFolder as NSString).standardizingPath

		// Source is in target if source path starts with target path followed by /
		// or if they're exactly equal
		return normalizedSource == normalizedTarget ||
			normalizedSource.hasPrefix(normalizedTarget + "/")
	}

	/* Check if a folder name suggests it's meant for view/UI files.
	 Matches folders named with UI keywords (ui, views, interface) or view-related patterns.
	 Used to prevent suggesting non-view files be moved into view/UI folders. */
	static func isUIOrViewFolder(folderName: String) -> Bool {
		let uiKeywords = ["ui", "views", "interface"]
		let lowercased = folderName.lowercased()
		return uiKeywords.contains { lowercased.contains($0) }
	}

	/* Check if any of the symbols conform to a view type (View, ViewModifier, etc).
	 Used to determine if a file containing these symbols is appropriate to move into a view/UI folder.
	 Only returns true for actual View types (struct/class), not extensions, protocols, or other declarations. */
	static func containsViewSymbols(_ symbols: [Declaration]) -> Bool {
		symbols.contains { symbol in
			// Only consider struct or class declarations (not extensions, protocols, etc.)
			let isActualType = symbol.kind == .struct || symbol.kind == .class
			let conformsToView = DeclarationIconHelper.conformsToView(symbol)
			return isActualType && conformsToView
		}
	}

	/* Build formatted detail strings for symbol references.
	 Groups symbols by their top-level parent type and consolidates file references.
	 Shows parent type name with consolidated file list.
	 Returns tuple of (details array, consolidated symbol count). */
	static func buildSymbolReferenceDetails(
		symbols: [Declaration],
		referenceAnalysis: ReferenceAnalysis
	) -> (details: [String], consolidatedCount: Int) {
		var details: [String] = []

		// Group symbols by their top-level parent container
		var symbolsByParent: [Declaration: [Declaration]] = [:]
		for symbol in symbols {
			let parent = findTopLevelContainer(for: symbol)
			symbolsByParent[parent, default: []].append(symbol)
		}

		// Sort by parent name for consistent ordering
		let sortedParents = symbolsByParent.keys.sorted { ($0.name ?? "") < ($1.name ?? "") }

		for parent in sortedParents {
			let symbolsInParent = symbolsByParent[parent] ?? []

			// Consolidate all reference files for symbols in this parent
			var allRefFiles = Set<String>()
			for symbol in symbolsInParent {
				if let refFiles = referenceAnalysis.symbolReferences[symbol] {
					allRefFiles.formUnion(refFiles)
				}
			}

			// Format parent name
			let parentName = (parent.name ?? "unknown").truncated(to: 40)

			// Show file names for 1-2 references, count for 3+
			if allRefFiles.count <= 2 {
				let fileNames = allRefFiles.sorted().map { ($0 as NSString).lastPathComponent }
				let fileList = fileNames.joined(separator: ", ")
				details.append("• \(parentName) ← \(fileList)")
			} else {
				details.append("• \(parentName) (\(allRefFiles.count) references)")
			}
		}

		return (details, symbolsByParent.count)
	}
}
