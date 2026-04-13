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
	 */
	func restoreAllCaches(for configurations: [PeripheryConfiguration]) {
		guard !noCache else { return }
		for config in configurations {
			let state = getState(for: config.id)
			guard !state.isRestoredFromCache, !state.isScanning else { continue }
			if let cache = ScanCacheManager.shared.load(for: config.id) {
				state.restoreFromCache(cache)
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
