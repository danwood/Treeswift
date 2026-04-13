//
//  AutomationActivityState.swift
//  Treeswift
//

import Foundation
import Observation

/**
 Tracks the currently active automation server command, if any.

 Set to a human-readable description when the server starts processing a request,
 cleared when the request completes. Observed by the UI to show an activity banner.
 */
@Observable
@MainActor
final class AutomationActivityState {
	var activeCommand: String?
}
