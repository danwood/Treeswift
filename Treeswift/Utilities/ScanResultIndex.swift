import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

/**
 Maintains an indexed mapping of scan results by file path for O(1) lookup performance.

 This class builds and maintains a dictionary mapping file paths to their associated scan results,
 eliminating the need for O(n) linear searches through all scan results when filtering or displaying
 results for a specific file.
 */
@Observable
final class ScanResultIndex {
	private var filePathIndex: [String: [ScanResult]] = [:]
	private var cachedFilteredResults: [String: [ScanResult]] = [:]
	private var lastFilterStateHash: Int = 0

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
	}

	/**
	 Returns all scan results associated with a specific file path.

	 - Parameter path: The file path to look up
	 - Returns: Array of scan results for the file, or empty array if none exist
	 */
	func results(forFile path: String) -> [ScanResult] {
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
	 Invalidates the filtered results cache when filter state changes.

	 - Parameter filterState: The new filter state
	 */
	func invalidateCache(for filterState: FilterState?) {
		let newHash = computeFilterHash(filterState: filterState, hiddenIDs: [])
		if newHash != lastFilterStateHash {
			cachedFilteredResults.removeAll()
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

		hasher.combine(hiddenIDs.count)

		return hasher.finalize()
	}
}
