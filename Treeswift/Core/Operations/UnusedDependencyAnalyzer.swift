//
//  UnusedDependencyAnalyzer.swift
//  Treeswift
//
//  Analyzes cross-references between unused declarations to support
//  safe code removal strategies.
//

import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

/**
 Strategy for handling unused declarations that are still referenced
 by other unused code.
 */
enum RemovalStrategy: Sendable {
	// Only remove declarations with no references from other code
	// (whether used or unused). Safest option — guarantees no build breakage.
	case skipReferenced

	// Remove all unused code regardless of cross-references.
	// Current behavior — fast but can break the build.
	case forceRemoveAll

	// Also remove unused declarations that reference the targets,
	// transitively up the call chain.
	case cascade
}

/**
 Result of filtering operations through the dependency analyzer.
 */
struct FilteredOperations {
	typealias Operation = (scanResult: ScanResult, declaration: Declaration, location: Location)

	// Operations safe to execute
	let operationsToExecute: [Operation]

	// Operations skipped (for skip strategy) with the count of references
	let skippedCount: Int

	// Additional files that need cascade processing
	let cascadeTargetsByFile: [String: [Declaration]]
}

/**
 A single symbol in a dependency chain, with enough info to display and navigate.
 */
struct ChainLink: Identifiable {
	let id: String
	let declaration: Declaration
	let name: String
	let filePath: String
	let line: Int
	let isInScope: Bool
	// True when references exist from outside the deletion batch
	let hasExternalReferences: Bool

	/**
	 Whether this link should show as strikethrough under the given strategy.
	 */
	func isStrikethrough(strategy: RemovalStrategy) -> Bool {
		switch strategy {
		case .skipReferenced:
			// Skip strategy: delete in-scope symbols that have no external references
			isInScope && !hasExternalReferences
		case .forceRemoveAll:
			// Force: only in-scope symbols are deleted
			isInScope
		case .cascade:
			// Cascade: all symbols in the chain are deleted
			true
		}
	}
}

/**
 A chain of unused symbols: index 0 is the leaf (the declaration targeted
 for deletion), subsequent links are its unused callers up to the root.
 */
struct DependencyChain: Identifiable {
	let id: String
	let links: [ChainLink]
}

/**
 Analyzes dependencies between unused declarations to determine
 which can be safely removed without breaking the build.
 */
enum UnusedDependencyAnalyzer {
	/**
	 Builds the set of all removable `.unused` declarations across the given file paths.

	 Used to provide batch context for `skipReferenced` strategy: when processing
	 a folder or multi-file batch, references between files within the same batch
	 should not count as "external". Pass the result as `batchDeletionSet` to
	 `filterOperations` / `removeAllUnusedCode`.

	 Does not apply a filter state — it captures the structural set of all declarations
	 that could be removed, regardless of current UI visibility settings.
	 */
	static func buildBatchDeletionSet(
		filePaths: Set<String>,
		scanResults: [ScanResult]
	) -> Set<Declaration> {
		var result = Set<Declaration>()
		for scanResult in scanResults {
			guard case .unused = scanResult.annotation else { continue }
			let declaration = scanResult.declaration
			let location = ScanResultHelper.location(from: declaration)
			guard filePaths.contains(location.file.path.string) else { continue }
			let hasFullRange = location.endLine != nil && location.endColumn != nil
			let isImport = declaration.kind == .module
			guard scanResult.annotation.canRemoveCode(
				hasFullRange: hasFullRange,
				isImport: isImport,
				location: location
			) else { continue }
			result.insert(declaration)
		}
		return result
	}

	/**
	 Filters a set of removal operations based on the chosen strategy.

	 For `.skipReferenced`: removes operations whose declarations are still
	 referenced by any declaration NOT in the deletion batch.

	 For `.forceRemoveAll`: passes all operations through unchanged.

	 For `.cascade`: identifies additional unused declarations in other files
	 that reference the targets, so they can be removed too.

	 The `batchDeletionSet` parameter provides the full set of declarations being
	 removed across all files in a batch operation. When provided, it is used as
	 the deletion context for cross-reference checking in `.skipReferenced` — so
	 a reference from another file in the same batch does not count as "external".
	 When nil, only the current file's declarations are used as context.
	 */
	static func filterOperations(
		operations: [FilteredOperations.Operation],
		strategy: RemovalStrategy,
		sourceGraph: (any SourceGraphProtocol)?,
		allUnusedDeclarations: Set<Declaration>?,
		batchDeletionSet: Set<Declaration>? = nil
	) -> FilteredOperations {
		switch strategy {
		case .forceRemoveAll:
			FilteredOperations(
				operationsToExecute: operations,
				skippedCount: 0,
				cascadeTargetsByFile: [:]
			)

		case .skipReferenced:
			filterSkipReferenced(
				operations: operations,
				sourceGraph: sourceGraph,
				allUnusedDeclarations: allUnusedDeclarations,
				batchDeletionSet: batchDeletionSet
			)

		case .cascade:
			filterCascade(
				operations: operations,
				sourceGraph: sourceGraph,
				allUnusedDeclarations: allUnusedDeclarations
			)
		}
	}

	/**
	 For the skip strategy: only keep operations where the declaration
	 has no references from code outside the deletion batch.

	 Uses `batchDeletionSet` when available (all declarations being removed
	 across all files in the batch), so cross-file references within the same
	 batch are not treated as "external". Falls back to the current file's
	 declarations only when no batch context is provided.
	 */
	private static func filterSkipReferenced(
		operations: [FilteredOperations.Operation],
		sourceGraph: (any SourceGraphProtocol)?,
		allUnusedDeclarations: Set<Declaration>?,
		batchDeletionSet: Set<Declaration>?
	) -> FilteredOperations {
		guard let sourceGraph else {
			// Without a source graph we cannot analyze references;
			// fall back to removing everything.
			return FilteredOperations(
				operationsToExecute: operations,
				skippedCount: 0,
				cascadeTargetsByFile: [:]
			)
		}

		// Use the full batch deletion set when available so that references
		// between files in the same batch are not treated as external.
		let deletionSet = batchDeletionSet ?? Set(operations.map(\.declaration))
		var kept: [FilteredOperations.Operation] = []
		var skippedCount = 0

		for op in operations {
			// Only apply skip logic to .unused annotations;
			// access-control fixes and ignore-comment removals are always safe.
			guard case .unused = op.scanResult.annotation else {
				kept.append(op)
				continue
			}

			if hasExternalReferences(op.declaration, deletionSet: deletionSet, sourceGraph: sourceGraph) {
				skippedCount += 1
			} else {
				kept.append(op)
			}
		}

		return FilteredOperations(
			operationsToExecute: kept,
			skippedCount: skippedCount,
			cascadeTargetsByFile: [:]
		)
	}

	/**
	 For the cascade strategy: find all unused declarations that reference
	 any of the target declarations, transitively, and group them by file.
	 The operations in the current file are passed through unchanged.
	 */
	private static func filterCascade(
		operations: [FilteredOperations.Operation],
		sourceGraph: (any SourceGraphProtocol)?,
		allUnusedDeclarations: Set<Declaration>?
	) -> FilteredOperations {
		guard let sourceGraph, let allUnusedDeclarations else {
			return FilteredOperations(
				operationsToExecute: operations,
				skippedCount: 0,
				cascadeTargetsByFile: [:]
			)
		}

		// Start with the declarations we're deleting
		var toDelete = Set(operations.map(\.declaration))
		var worklist = Array(toDelete)

		// Transitively find unused declarations that reference our targets
		while let current = worklist.popLast() {
			let refs = sourceGraph.references(to: current)
			for ref in refs {
				guard let parent = ref.parent else { continue }
				// Only cascade to declarations that are also unused
				guard allUnusedDeclarations.contains(parent) else { continue }
				if toDelete.insert(parent).inserted {
					worklist.append(parent)
				}
			}
		}

		// Separate cascaded declarations by file, excluding the current file
		let currentFilePath = operations.first.map {
			ScanResultHelper.location(from: $0.declaration).file.path.string
		}

		var cascadeByFile: [String: [Declaration]] = [:]
		for decl in toDelete {
			let loc = ScanResultHelper.location(from: decl)
			let path = loc.file.path.string
			guard path != currentFilePath else { continue }
			// Only include declarations that already exist in the operations set
			// are NOT in the current batch (those are handled normally)
			cascadeByFile[path, default: []].append(decl)
		}

		return FilteredOperations(
			operationsToExecute: operations,
			skippedCount: 0,
			cascadeTargetsByFile: cascadeByFile
		)
	}

	/**
	 Builds dependency chains for display in the Details section.

	 Each chain starts with a leaf declaration (one targeted for removal)
	 and walks upward through unused callers via the source graph.
	 Chains are deduplicated so each declaration appears only once,
	 prioritizing longer chains. The result is sorted by leaf file path
	 then line number.
	 */
	static func buildDependencyChains(
		operations: [FilteredOperations.Operation],
		sourceGraph: (any SourceGraphProtocol)?,
		allUnusedDeclarations: Set<Declaration>?,
		scopePath: String
	) -> [DependencyChain] {
		guard let sourceGraph else { return [] }
		let unusedSet = allUnusedDeclarations ?? []

		// Collect leaf declarations from .unused operations
		let leafDeclarations = operations.compactMap { op -> Declaration? in
			guard case .unused = op.scanResult.annotation else { return nil }
			return op.declaration
		}

		// Build raw chains (each is a path from leaf up to root caller)
		var rawChains: [[Declaration]] = []
		for leaf in leafDeclarations {
			let paths = walkUpCallers(
				from: leaf,
				sourceGraph: sourceGraph,
				unusedSet: unusedSet
			)
			if paths.isEmpty {
				// True leaf with no unused callers
				rawChains.append([leaf])
			} else {
				rawChains.append(contentsOf: paths)
			}
		}

		// Sort by chain length descending so longer chains claim declarations first
		rawChains.sort { $0.count > $1.count }

		// Deduplicate: each declaration appears in at most one chain
		var seen = Set<ObjectIdentifier>()
		var dedupedChains: [[Declaration]] = []

		for chain in rawChains {
			let leafID = ObjectIdentifier(chain[0])
			if seen.contains(leafID) { continue }

			// Always keep the leaf; filter out already-seen non-leaf links
			var filtered = [chain[0]]
			seen.insert(leafID)
			for decl in chain.dropFirst() {
				let declID = ObjectIdentifier(decl)
				if seen.insert(declID).inserted {
					filtered.append(decl)
				}
			}
			dedupedChains.append(filtered)
		}

		// Build the in-scope deletion set for external reference checking
		let inScopeDeclSet = Set(operations.map(\.declaration))

		// Convert to DependencyChain models
		var result = dedupedChains.map { chain -> DependencyChain in
			let links = chain.map { decl -> ChainLink in
				let loc = ScanResultHelper.location(from: decl)
				let filePath = loc.file.path.string
				let name = decl.name ?? decl.kind.displayName
				let hasExtRefs = hasExternalReferences(
					decl,
					deletionSet: inScopeDeclSet,
					sourceGraph: sourceGraph
				)
				return ChainLink(
					id: "\(filePath):\(loc.line):\(name)",
					declaration: decl,
					name: name,
					filePath: filePath,
					line: loc.line,
					isInScope: filePath.hasPrefix(scopePath),
					hasExternalReferences: hasExtRefs
				)
			}
			return DependencyChain(
				id: links.map(\.id).joined(separator: "→"),
				links: links
			)
		}

		// Sort by leaf file path, then line number
		result.sort { a, b in
			guard let aLeaf = a.links.first, let bLeaf = b.links.first else { return false }
			if aLeaf.filePath != bLeaf.filePath {
				return aLeaf.filePath < bLeaf.filePath
			}
			return aLeaf.line < bLeaf.line
		}

		return result
	}

	/**
	 Walks upward from a declaration through its unused callers,
	 returning all paths from the leaf to a root (a caller with no
	 further unused callers).
	 */
	private static func walkUpCallers(
		from declaration: Declaration,
		sourceGraph: any SourceGraphProtocol,
		unusedSet: Set<Declaration>,
		visited: Set<ObjectIdentifier> = []
	) -> [[Declaration]] {
		let refs = sourceGraph.references(to: declaration)
		let unusedParents = refs.compactMap { ref -> Declaration? in
			guard let parent = ref.parent else { return nil }
			guard unusedSet.contains(parent) else { return nil }
			guard !visited.contains(ObjectIdentifier(parent)) else { return nil }
			return parent
		}

		if unusedParents.isEmpty { return [] }

		var paths: [[Declaration]] = []
		var newVisited = visited
		newVisited.insert(ObjectIdentifier(declaration))

		for parent in unusedParents {
			let upPaths = walkUpCallers(
				from: parent,
				sourceGraph: sourceGraph,
				unusedSet: unusedSet,
				visited: newVisited
			)
			if upPaths.isEmpty {
				// parent is the root of this chain
				paths.append([declaration, parent])
			} else {
				for path in upPaths {
					paths.append([declaration] + path)
				}
			}
		}

		return paths
	}

	/**
	 Checks whether a declaration has references from any declaration
	 that is NOT in the deletion batch.
	 */
	private static func hasExternalReferences(
		_ declaration: Declaration,
		deletionSet: Set<Declaration>,
		sourceGraph: any SourceGraphProtocol
	) -> Bool {
		let refs = sourceGraph.references(to: declaration)
		for ref in refs {
			guard let parent = ref.parent else { continue }
			// If the referencing declaration is not being deleted, this is external
			if !deletionSet.contains(parent) {
				return true
			}
		}
		return false
	}
}
