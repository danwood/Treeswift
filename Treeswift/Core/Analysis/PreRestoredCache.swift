//
//	PreRestoredCache.swift
//	Treeswift
//
//	Holds the results of the expensive off-main-actor cache deserialization.
//	Created from a ScanCache on a background thread, then applied to ScanState
//	cheaply on the main actor via applyPreRestoredCache(_:).
//

import Foundation
import PeripheryKit
import SourceGraph

/// Pre-computed, fully deserialized cache ready to be applied to a ScanState.
/// All construction happens off the main actor; applying to ScanState is cheap.
nonisolated struct PreRestoredCache: Sendable {
	let projectPath: String?
	let cachedAt: Date
	let treeNodes: [TreeNode]
	let treeSection: CategoriesNode?
	let viewExtensionsSection: CategoriesNode?
	let sharedSection: CategoriesNode?
	let orphansSection: CategoriesNode?
	let previewOrphansSection: CategoriesNode?
	let bodyGetterSection: CategoriesNode?
	let unattachedSection: CategoriesNode?
	let fileTreeNodes: [FileBrowserNode]
	let sourceGraph: (any SourceGraphProtocol)?
	let scanResults: [ScanResult]

	nonisolated init(from cache: ScanCache, progress: (@MainActor (Double, String) -> Void)? = nil) async {
		projectPath = cache.projectPath
		cachedAt = cache.cachedAt
		if let progress { await MainActor.run { progress(0.0, "Restoring tree nodes…") } }
		treeNodes = cache.restoreTreeNodes()
		treeSection = cache.treeSection.map { cache.restoreCategoriesNode($0) }
		viewExtensionsSection = cache.viewExtensionsSection.map { cache.restoreCategoriesNode($0) }
		sharedSection = cache.sharedSection.map { cache.restoreCategoriesNode($0) }
		orphansSection = cache.orphansSection.map { cache.restoreCategoriesNode($0) }
		previewOrphansSection = cache.previewOrphansSection.map { cache.restoreCategoriesNode($0) }
		bodyGetterSection = cache.bodyGetterSection.map { cache.restoreCategoriesNode($0) }
		unattachedSection = cache.unattachedSection.map { cache.restoreCategoriesNode($0) }
		fileTreeNodes = cache.restoreFileTreeNodes()
		if let progress { await MainActor.run { progress(0.2, "Restoring source graph…") } }
		if let restored = await SourceGraphSerializer.restore(
			declarationSnapshots: cache.declarationSnapshots,
			referenceSnapshots: cache.referenceSnapshots,
			scanResultSnapshots: cache.scanResultSnapshots,
			progress: { fraction, label in progress?(0.2 + fraction * 0.8, label) }
		) {
			sourceGraph = restored.sourceGraph
			scanResults = restored.scanResults
		} else {
			sourceGraph = nil
			scanResults = []
		}
	}
}
