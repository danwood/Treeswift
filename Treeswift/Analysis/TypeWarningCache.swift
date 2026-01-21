//
//  TypeWarningCache.swift
//  Treeswift
//
//  Builds hash-based cache for fast type warning lookups
//
//  PURPOSE:
//  This cache provides O(1) lookup of Periphery warnings for top-level symbols during
//  file tree analysis. When enriching the file browser with type information, we need to
//  determine if each top-level symbol has associated Periphery warnings. Without this cache,
//  we would need O(n) linear search through all ScanResults for each symbol lookup.
//
//  The cache is built once during file tree enrichment and then used for fast lookups
//  as we process each symbol in each file.
//

import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

/**
 Key for looking up warning status by symbol name and file path.

 A symbol is uniquely identified by its name and the file it's declared in.
 This allows the same symbol name to exist in different files without collision.
 */
nonisolated struct TypeWarningKey: Hashable, Sendable {
	let typeName: String
	let filePath: String

	func hash(into hasher: inout Hasher) {
		hasher.combine(typeName)
		hasher.combine(filePath)
	}

	static func == (lhs: TypeWarningKey, rhs: TypeWarningKey) -> Bool {
		lhs.typeName == rhs.typeName && lhs.filePath == rhs.filePath
	}
}

/**
 Warning status for a single top-level symbol.

 Stores all warning types that apply to this symbol. A symbol can have multiple warnings
 (e.g., both .unused and .redundantAccessControl), so we use a Set to track all of them.

 Uses FilterState.WarningType instead of ScanResult.Annotation because it consolidates
 related annotation types into user-friendly categories (e.g., all four redundant
 accessibility annotations map to a single .redundantAccessControl warning type).
 */
struct TypeWarningStatus: Sendable {
	let warningTypes: Set<FilterState.WarningType>
}

final class TypeWarningCache: Sendable {
	/**
	 Builds a hash-based lookup cache from Periphery scan results.

	 This method processes all ScanResults and creates a dictionary keyed by (typeName, filePath)
	 that allows O(1) lookup of warning status for any top-level symbol.

	 WHY THIS IS NEEDED:
	 During file tree enrichment (FileTypeAnalyzer.enrichFilesWithTypeInfo), we process hundreds
	 or thousands of files, each containing multiple top-level symbols. For each symbol, we need
	 to check if it has any Periphery warnings. Without this cache, we would need to iterate
	 through all ScanResults for each symbol (O(n*m) complexity). The cache reduces this to O(n+m).

	 HOW IT WORKS:
	 1. Iterate through all ScanResults once to build the cache
	 2. For each ScanResult, extract the symbol name and file path to create a TypeWarningKey
	 3. Convert the ScanResult.Annotation to FilterState.WarningType (consolidates 8 annotation
	    cases into 5 user-friendly warning types)
	 4. If a symbol has multiple warnings, use set union to merge them (a symbol can have
	    multiple different warning types)

	 - Parameter scanResults: All Periphery scan results from the analysis
	 - Returns: Dictionary mapping (symbol name, file path) to set of warning types
	 */
	nonisolated static func buildCache(from scanResults: [ScanResult]) -> [TypeWarningKey: TypeWarningStatus] {
		var cache: [TypeWarningKey: TypeWarningStatus] = [:]

		for result in scanResults {
			let decl = result.declaration
			guard let typeName = decl.name else { continue }

			let filePath = decl.location.file.path.string
			let key = TypeWarningKey(typeName: typeName, filePath: filePath)

			// Convert annotation to user-friendly warning type.
			// This consolidates the 8 ScanResult.Annotation cases into 5 FilterState.WarningType cases.
			// For example, all four redundant accessibility annotations (.redundantPublicAccessibility,
			// .redundantInternalAccessibility, .redundantFilePrivateAccessibility, .redundantAccessibility)
			// map to a single .redundantAccessControl warning type.
			let warningType = result.annotation.warningType

			// Merge with existing status (a symbol can have multiple warnings).
			// For example, a symbol might be both .unused AND .redundantAccessControl.
			// We use set union to preserve all warnings.
			if let existing = cache[key] {
				cache[key] = TypeWarningStatus(
					warningTypes: existing.warningTypes.union([warningType])
				)
			} else {
				cache[key] = TypeWarningStatus(
					warningTypes: [warningType]
				)
			}
		}

		return cache
	}
}
