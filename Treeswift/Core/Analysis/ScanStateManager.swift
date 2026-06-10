//
//  ScanStateManager.swift
//  Treeswift
//
//  Manages scan states for all configurations
//  Provides lifecycle management and cleanup for concurrent scans
//

import Foundation

@Observable
@MainActor
final class ScanStateManager {
	private var states: [UUID: ScanState] = [:]
	private let noCache: Bool
	private var cacheRestoreTask: Task<Void, Never>?

	/// True while caches are being loaded at startup.
	var isRestoringCaches = false
	/// Human-readable status shown in the startup progress panel.
	var cacheRestoreStatus = ""
	/// Number of caches loaded so far during startup restore.
	var cacheRestoreLoaded = 0
	/// Total number of caches to load during startup restore.
	var cacheRestoreTotal = 0

	init(noCache: Bool = false) {
		self.noCache = noCache
	}

	/// Get or create scan state for a configuration
	///
	/// Returns the existing state if available, otherwise creates a new one.
	/// This allows scan results to persist when switching between configurations.
	func getState(for configurationID: UUID) -> ScanState {
		if let state = states[configurationID] {
			return state
		}
		let newState = ScanState(configurationID: configurationID)
		states[configurationID] = newState
		return newState
	}

	/**
	 Eagerly loads caches for all known configurations.
	 Call this at app startup so results are available before the first render.
	 Updates isRestoringCaches / cacheRestoreStatus so the UI can show a progress panel.

	 Only one cache is loaded per unique project path — the most recently cached one.
	 Older duplicate caches for the same project are deleted from disk.

	 All expensive work (JSON decoding, graph restoration) runs off the main actor.
	 Only the final state assignments touch the main actor.
	 */
	func restoreAllCaches(for configurations: [PeripheryConfiguration]) {
		guard !noCache else { return }
		let pending = configurations.filter { config in
			let state = getState(for: config.id)
			return !state.isRestoredFromCache && !state.isScanning
		}
		guard !pending.isEmpty else { return }
		isRestoringCaches = true
		cacheRestoreLoaded = 0
		cacheRestoreTotal = 0 // updated once we know how many have actual cache files
		cacheRestoreStatus = "Checking cached results…"

		// Use Task.detached so the restore work and withTaskGroup children run on background
		// executor threads, not on the main actor. All state mutations hop back via MainActor.run.
		cacheRestoreTask = Task.detached(priority: .userInitiated) { [weak self] in
			guard let self else { return }

			// Step 1 (background): load raw cache data and deduplicate by project path.
			var bestByPath: [String: (config: PeripheryConfiguration, cache: ScanCache)] = [:]
			for config in pending {
				guard let cache = ScanCacheManager.shared.load(for: config.id) else { continue }
				let key = config.project ?? config.name
				if let existing = bestByPath[key] {
					if cache.cachedAt > existing.cache.cachedAt {
						ScanCacheManager.shared.delete(for: existing.config.id)
						bestByPath[key] = (config, cache)
					} else {
						ScanCacheManager.shared.delete(for: config.id)
					}
				} else {
					bestByPath[key] = (config, cache)
				}
			}
			let loaded = Array(bestByPath.values)

			// Update count now that we know how many caches actually exist.
			await MainActor.run {
				self.cacheRestoreTotal = loaded.count
				self.cacheRestoreLoaded = 0
			}

			guard !loaded.isEmpty else {
				await MainActor.run {
					self.isRestoringCaches = false
					self.cacheRestoreStatus = ""
				}
				return
			}

			// Step 2: restore each cache concurrently on background threads
			// (group.addTask inherits nonisolated context from detached task),
			// then apply results on the main actor one at a time.
			await withTaskGroup(of: (PeripheryConfiguration, PreRestoredCache).self) { group in
				for (config, cache) in loaded {
					let configName = URL(fileURLWithPath: config.project ?? config.name)
						.deletingPathExtension().lastPathComponent
					group.addTask(priority: .userInitiated) {
						// Runs on background thread — PreRestoredCache.init is nonisolated.
						let pre = await PreRestoredCache(from: cache) { @MainActor _, label in
							self.cacheRestoreStatus = "\(configName): \(label)"
						}
						return (config, pre)
					}
				}
				for await (config, pre) in group {
					guard !Task.isCancelled else { break }
					let name = URL(fileURLWithPath: config.project ?? config.name)
						.deletingPathExtension().lastPathComponent
					await MainActor.run {
						self.cacheRestoreStatus = "Applying \(name)…"
						let state = self.getState(for: config.id)
						state.applyPreRestoredCache(pre)
						self.cacheRestoreLoaded += 1
					}
				}
			}

			if !Task.isCancelled {
				await MainActor.run {
					self.isRestoringCaches = false
					self.cacheRestoreStatus = ""
				}
			}
		}
	}

	/**
	 Cancels an in-progress cache restore, clears all on-disk caches,
	 and resets progress state. The app starts fresh with no cached results.
	 */
	func cancelCacheRestore(for configurations: [PeripheryConfiguration]) {
		cacheRestoreTask?.cancel()
		cacheRestoreTask = nil
		isRestoringCaches = false
		cacheRestoreStatus = ""
		cacheRestoreLoaded = 0
		cacheRestoreTotal = 0
		Task.detached(priority: .background) {
			for config in configurations {
				ScanCacheManager.shared.delete(for: config.id)
			}
		}
	}

	/// True if any configuration is currently scanning
	var isAnyScanning: Bool {
		states.values.contains { $0.isScanning }
	}

	/// Remove scan state when configuration is deleted
	///
	/// Cancels any running scan and removes the state from memory.
	func removeState(for configurationID: UUID) {
		states[configurationID]?.stopScan()
		states.removeValue(forKey: configurationID)
	}
}
