//
//  WarningStateManager.swift
//  Treeswift
//
//  Centralized state management for warning completion/restoration.
//

import Foundation

/**
 Manages state transitions for periphery warnings.

 Centralizes the pattern of marking warnings as completed or restored,
 including updating state collections and posting notifications.
 */
struct WarningStateManager {
	/**
	 Marks a warning as completed.

	 Updates state collections to hide the warning and posts a completion notification.
	 */
	static func completeWarning(
		warningID: String,
		completedActions: inout Set<String>,
		removingWarnings: inout Set<String>
	) {
		completedActions.insert(warningID)
		removingWarnings.remove(warningID)

		NotificationCenter.default.post(
			name: Notification.Name("PeripheryWarningCompleted"),
			object: warningID
		)
	}

	/**
	 Restores a warning (reverses completion).

	 Updates state collections to show the warning again and posts a restoration notification.
	 */
	static func restoreWarning(
		warningID: String,
		completedActions: inout Set<String>,
		removingWarnings: inout Set<String>
	) {
		completedActions.remove(warningID)
		removingWarnings.remove(warningID)

		NotificationCenter.default.post(
			name: Notification.Name("PeripheryWarningRestored"),
			object: warningID
		)
	}
}
