//
//  ScanCacheManager.swift
//  Treeswift
//
//  Manages reading and writing per-configuration scan caches to disk.
//  Cache files live at: ~/Library/Application Support/Treeswift/ScanCache/scan-cache-<UUID>.json
//

import Foundation

final nonisolated class ScanCacheManager: Sendable {
	static let shared = ScanCacheManager()

	private let cacheDirectory: URL

	private init() {
		let appSupport = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first!
		cacheDirectory = appSupport
			.appendingPathComponent("Treeswift", isDirectory: true)
			.appendingPathComponent("ScanCache", isDirectory: true)
		try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
	}

	// MARK: - Public API

	/**
	 Saves a scan cache to disk for the given configuration.
	 Uses atomic write to prevent partial files on crash.
	 */
	func save(_ cache: ScanCache) throws {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(cache)
		try data.write(to: cacheFileURL(for: cache.configurationID), options: .atomic)
		"* ✓ Scan results cached to disk (\(data.count) bytes)".logToConsole()
	}

	/**
	 Loads the cached scan results for the given configuration ID.
	 Returns nil if no cache exists, the file is unreadable, or the schema version is outdated.
	 */
	func load(for configurationID: UUID) -> ScanCache? {
		let url = cacheFileURL(for: configurationID)
		guard FileManager.default.fileExists(atPath: url.path) else { return nil }
		do {
			let data = try Data(contentsOf: url)
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			let cache = try decoder.decode(ScanCache.self, from: data)
			guard cache.schemaVersion == ScanCache.currentSchemaVersion else {
				try? FileManager.default.removeItem(at: url)
				return nil
			}
			return cache
		} catch {
			return nil
		}
	}

	/**
	 Deletes the cache file for the given configuration ID.
	 Failure is silently ignored — missing cache is correct behavior.
	 */
	func delete(for configurationID: UUID) {
		try? FileManager.default.removeItem(at: cacheFileURL(for: configurationID))
	}

	// MARK: - Private

	private func cacheFileURL(for id: UUID) -> URL {
		cacheDirectory.appendingPathComponent("scan-cache-\(id.uuidString).json")
	}
}
