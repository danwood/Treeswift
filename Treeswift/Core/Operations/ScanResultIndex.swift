import Foundation
import PeripheryKit
import SourceGraph
import SwiftUI
import SystemPackage

/**
 Maintains an indexed mapping of scan results by file path for O(1) lookup performance.

 This class builds and maintains a dictionary mapping file paths to their associated scan results,
 eliminating the need for O(n) linear searches through all scan results when filtering or displaying
 results for a specific file.
 */
@Observable
@MainActor
final class ScanResultIndex {
	private var filePathIndex: [String: [ScanResult]] = [:]
	private var cachedFilteredResults: [String: [ScanResult]] = [:]
	private var cachedBadges: [String: [Badge]] = [:]
	private var lastFilterStateHash: Int = 0

	private static let badgeOrderIndex: [SwiftType: Int] = [
		.struct: 0,
		.class: 1,
		.enum: 2,
		.typealias: 3,
		.extension: 4,
		.parameter: 5,
		.property: 6,
		.initializer: 7,
		.function: 8
	]

	/**
	 Rebuilds the index from a new set of scan results.

	 - Parameter results: The complete set of scan results to index
	 */
	func rebuild(from results: [ScanResult]) {
		var newIndex: [String: [ScanResult]] = [:]

		for result in results {
			let declaration = result.declaration
			let location = ScanResultHelper.location(from: declaration)
			let filePath = location.file.path.string

			newIndex[filePath, default: []].append(result)
		}

		filePathIndex = newIndex
		cachedFilteredResults.removeAll()
		cachedBadges.removeAll()
	}

	/**
	 Returns all scan results associated with a specific file path.

	 - Parameter path: The file path to look up
	 - Returns: Array of scan results for the file, or empty array if none exist
	 */
	private func results(forFile path: String) -> [ScanResult] {
		filePathIndex[path] ?? []
	}

	/**
	 Returns filtered scan results for a file, using cache when possible.

	 - Parameters:
	   - path: The file path to look up
	   - filterState: The current filter state to apply
	   - hiddenWarningIDs: Set of warning IDs to exclude
	 - Returns: Array of scan results matching all filters
	 */
	func filteredResults(
		forFile path: String,
		filterState: FilterState?,
		hiddenWarningIDs: Set<String>
	) -> [ScanResult] {
		let filterHash = computeFilterHash(filterState: filterState, hiddenIDs: hiddenWarningIDs)
		let cacheKey = "\(path):\(filterHash)"

		if let cached = cachedFilteredResults[cacheKey] {
			return cached
		}

		let fileResults = results(forFile: path)
		let filtered = filterResults(
			fileResults,
			filterState: filterState,
			hiddenWarningIDs: hiddenWarningIDs,
			filePath: path
		)

		cachedFilteredResults[cacheKey] = filtered
		return filtered
	}

	/**
	 Returns removable scan results for a file, ignoring topLevelOnly.

	 Used during batch removal to find all warnings that should be fixed,
	 including nested declarations that topLevelOnly would hide from the UI.
	 */
	func filteredResultsForRemoval(
		forFile path: String,
		filterState: FilterState?,
		hiddenWarningIDs: Set<String>
	) -> [ScanResult] {
		let fileResults = results(forFile: path)
		return fileResults.filter { scanResult in
			let declaration = scanResult.declaration

			if let filterState, !filterState.shouldShowForRemoval(scanResult: scanResult, declaration: declaration) {
				return false
			}

			let usr = declaration.usrs.first ?? ""
			let warningID = "\(path):\(usr)"
			if hiddenWarningIDs.contains(warningID) {
				return false
			}

			return true
		}
	}

	/**
	 Invalidates the filtered results cache when filter state changes.

	 - Parameter filterState: The new filter state
	 */
	func invalidateCache(for filterState: FilterState?) {
		let newHash = computeFilterHash(filterState: filterState, hiddenIDs: [])
		if newHash != lastFilterStateHash {
			cachedFilteredResults.removeAll()
			cachedBadges.removeAll()
			lastFilterStateHash = newHash
		}
	}

	/**
	 Filters an array of scan results based on current filter state and hidden warnings.

	 This combines all filtering logic into a single pass for efficiency.
	 */
	private func filterResults(
		_ results: [ScanResult],
		filterState: FilterState?,
		hiddenWarningIDs: Set<String>,
		filePath: String
	) -> [ScanResult] {
		results.filter { scanResult in
			let declaration = scanResult.declaration

			// Apply filter state if present
			if let filterState, !filterState.shouldShow(scanResult: scanResult, declaration: declaration) {
				return false
			}

			// Filter out hidden warnings
			let usr = declaration.usrs.first ?? ""
			let warningID = "\(filePath):\(usr)"
			if hiddenWarningIDs.contains(warningID) {
				return false
			}

			return true
		}
	}

	/**
	 Returns a snapshot of the raw file-path index for use off the main actor.
	 The snapshot is a value-type copy safe to pass across concurrency boundaries.
	 */
	func snapshotIndex() -> [String: [ScanResult]] {
		filePathIndex
	}

	/**
	 Returns cached badge array for a file, computing and caching on first call per filter state.
	 Avoids per-render badge recomputation in FileRowView.
	 */
	func visibleBadges(
		forFile path: String,
		filterState: FilterState?,
		hiddenWarningIDs: Set<String>
	) -> [Badge] {
		let filterHash = computeFilterHash(filterState: filterState, hiddenIDs: hiddenWarningIDs)
		let cacheKey = "\(path):\(filterHash)"

		if let cached = cachedBadges[cacheKey] {
			return cached
		}

		struct CounterKey: Hashable {
			let swiftType: SwiftType
			let isUnused: Bool
		}

		let visibleResults = filteredResults(
			forFile: path,
			filterState: filterState,
			hiddenWarningIDs: hiddenWarningIDs
		)

		var counts: [CounterKey: Int] = [:]
		counts.reserveCapacity(visibleResults.count)
		for result in visibleResults {
			let swiftType = SwiftType.from(declarationKind: result.declaration.kind)
			let key = CounterKey(swiftType: swiftType, isUnused: result.annotation == .unused)
			counts[key, default: 0] += 1
		}

		var badges: [Badge] = []
		badges.reserveCapacity(counts.count)
		for swiftType in SwiftType.allCases {
			if let c = counts[CounterKey(swiftType: swiftType, isUnused: true)], c > 0 {
				badges.append(Badge(letter: swiftType.rawValue, count: c, swiftType: swiftType, isUnused: true))
			}
			if let c = counts[CounterKey(swiftType: swiftType, isUnused: false)], c > 0 {
				badges.append(Badge(letter: swiftType.rawValue, count: c, swiftType: swiftType, isUnused: false))
			}
		}
		badges.sort {
			let l = Self.badgeOrderIndex[$0.swiftType] ?? Int.max
			let r = Self.badgeOrderIndex[$1.swiftType] ?? Int.max
			return l < r
		}

		cachedBadges[cacheKey] = badges
		return badges
	}

	/**
	 Computes a hash for filter state to use in cache keys.
	 */
	private func computeFilterHash(filterState: FilterState?, hiddenIDs: Set<String>) -> Int {
		var hasher = Hasher()

		if let filterState {
			hasher.combine(filterState.showUnused)
			hasher.combine(filterState.showAssignOnly)
			hasher.combine(filterState.showRedundantProtocol)
			hasher.combine(filterState.showRedundantAccessControl)
			hasher.combine(filterState.showSuperfluousIgnoreCommand)
			hasher.combine(filterState.topLevelOnly)
			hasher.combine(filterState.showStruct)
			hasher.combine(filterState.showClass)
			hasher.combine(filterState.showEnum)
			hasher.combine(filterState.showProtocol)
			hasher.combine(filterState.showExtension)
			hasher.combine(filterState.showProperty)
			hasher.combine(filterState.showFunction)
			hasher.combine(filterState.showTypealias)
			hasher.combine(filterState.showParameter)
			hasher.combine(filterState.showInitializer)
			hasher.combine(filterState.showImport)
		}

		hasher.combine(hiddenIDs.hashValue)

		return hasher.finalize()
	}
}
