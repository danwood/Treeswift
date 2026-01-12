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

	init() {
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

	/// Remove scan state when configuration is deleted
	///
	/// Cancels any running scan and removes the state from memory.
	func removeState(for configurationID: UUID) {
		states[configurationID]?.stopScan()
		states.removeValue(forKey: configurationID)
	}
}
