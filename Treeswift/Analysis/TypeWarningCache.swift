//
//  TypeWarningCache.swift
//  Treeswift
//
//  Builds hash-based cache for fast type warning lookups
//

import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

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

struct TypeWarningStatus: Sendable {
	let isUnused: Bool
	let isRedundantPublic: Bool
}

// periphery:ignore
final class TypeWarningCache: Sendable {
	nonisolated static func buildCache(from scanResults: [ScanResult]) -> [TypeWarningKey: TypeWarningStatus] {
		var cache: [TypeWarningKey: TypeWarningStatus] = [:]

		// periphery:ignore
		for result in scanResults {
			let decl = result.declaration
			guard let typeName = decl.name else { continue }

			let filePath = decl.location.file.path.string
			let key = TypeWarningKey(typeName: typeName, filePath: filePath)

			// Weirdly expressed to avoid: Main actor-isolated conformance of 'ScanResult.Annotation'
			// to 'RawRepresentable' cannot be used in nonisolated context
			let isUnused = if case .unused = result.annotation { true } else { false }
			let isRedundantPublic = if case .redundantPublicAccessibility = result.annotation { true } else { false }

			// Merge with existing status (a type can have multiple warnings)
			if let existing = cache[key] {
				cache[key] = TypeWarningStatus(
					isUnused: existing.isUnused || isUnused,
					isRedundantPublic: existing.isRedundantPublic || isRedundantPublic
				)
			} else {
				cache[key] = TypeWarningStatus(
					isUnused: isUnused,
					isRedundantPublic: isRedundantPublic
				)
			}
		}

		return cache
	}
}
