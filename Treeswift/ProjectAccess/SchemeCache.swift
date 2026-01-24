//
//  SchemeCache.swift
//  Treeswift
//
//  Persistent cache for Xcode project schemes with modification date tracking
//

import Foundation

@MainActor
class SchemeCache {
	static let shared = SchemeCache()

	// Cache entry stores schemes along with metadata for invalidation
	private struct CacheEntry: Codable, Sendable {
		let schemes: [String]
		let schemesDirectoryModificationDate: Date
	}

	// All cache entries keyed by project path
	private struct CacheStorage: Codable, Sendable {
		var entries: [String: CacheEntry]
	}

	private var storage: CacheStorage
	private let cacheFileURL: URL

	private init() {
		// Set up cache file location in Application Support
		let appSupport = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first!
		let appFolder = appSupport.appendingPathComponent("Treeswift", isDirectory: true)

		// Create directory if needed
		try? FileManager.default.createDirectory(
			at: appFolder,
			withIntermediateDirectories: true
		)

		cacheFileURL = appFolder.appendingPathComponent("scheme-cache.json")

		// Load existing cache from disk
		storage = Self.loadFromDisk(at: cacheFileURL) ?? CacheStorage(entries: [:])
	}

	/// Get cached schemes for a project path, validating modification date
	/// - Parameter path: Full path to .xcodeproj or .xcworkspace
	/// - Returns: Cached schemes if valid, nil if cache is stale or missing
	func get(forPath path: String) -> [String]? {
		guard let entry = storage.entries[path] else {
			return nil
		}

		// Check if schemes directory still exists and hasn't been modified
		guard let currentModDate = getSchemesDirectoryModificationDate(forProjectPath: path) else {
			// Directory doesn't exist or can't be read - invalidate cache
			storage.entries.removeValue(forKey: path)
			saveToDisk()
			return nil
		}

		// Compare modification dates (truncate to seconds for filesystem compatibility)
		let cachedModDate = entry.schemesDirectoryModificationDate
		if abs(currentModDate.timeIntervalSince(cachedModDate)) > 1.0 {
			// Schemes directory has been modified - cache is stale
			storage.entries.removeValue(forKey: path)
			saveToDisk()
			return nil
		}

		// Cache is valid
		return entry.schemes
	}

	/// Set cached schemes for a project path with current modification date
	/// - Parameters:
	///   - schemes: Array of scheme names
	///   - path: Full path to .xcodeproj or .xcworkspace
	func set(schemes: [String], forPath path: String) {
		guard let modDate = getSchemesDirectoryModificationDate(forProjectPath: path) else {
			// Can't get modification date - don't cache
			return
		}

		let entry = CacheEntry(
			schemes: schemes,
			schemesDirectoryModificationDate: modDate
		)

		storage.entries[path] = entry
		saveToDisk()
	}

	/// Invalidate cache entry for a specific path
	private func invalidate(path: String) {
		storage.entries.removeValue(forKey: path)
		saveToDisk()
	}

	/// Invalidate cache entry for an optional path (convenience method)
	func invalidateIfNeeded(path: String?) {
		if let path {
			invalidate(path: path)
		}
	}

	// MARK: - Modification Date Tracking

	/// Get the modification date of the xcshareddata/xcschemes directory
	/// - Parameter projectPath: Full path to .xcodeproj or .xcworkspace
	/// - Returns: Modification date, or nil if directory doesn't exist or can't be accessed
	private func getSchemesDirectoryModificationDate(forProjectPath projectPath: String) -> Date? {
		let projectURL = URL(fileURLWithPath: projectPath)
		let schemesURL = projectURL
			.appendingPathComponent("xcshareddata", isDirectory: true)
			.appendingPathComponent("xcschemes", isDirectory: true)

		do {
			let attributes = try FileManager.default.attributesOfItem(atPath: schemesURL.path)
			return attributes[.modificationDate] as? Date
		} catch {
			// Directory doesn't exist or can't be accessed
			return nil
		}
	}

	// MARK: - Persistent Storage

	/// Save cache to disk
	private func saveToDisk() {
		do {
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .iso8601
			let data = try encoder.encode(storage)
			try data.write(to: cacheFileURL, options: .atomic)
		} catch {
			print("Failed to save scheme cache: \(error)")
		}
	}

	/// Load cache from disk
	/// - Parameter url: URL of cache file
	/// - Returns: Loaded cache storage, or nil if file doesn't exist or can't be decoded
	private static func loadFromDisk(at url: URL) -> CacheStorage? {
		guard FileManager.default.fileExists(atPath: url.path) else {
			return nil
		}

		do {
			let data = try Data(contentsOf: url)
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			return try decoder.decode(CacheStorage.self, from: data)
		} catch {
			print("Failed to load scheme cache: \(error)")
			return nil
		}
	}
}
