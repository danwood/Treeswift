//
//  SearchNavigationState.swift
//  Treeswift
//
//  Model owning toolbar search query, results, and navigation requests.
//  Owned as @State in ContentView and passed down to tree views.
//

import Foundation

@Observable @MainActor
final class SearchNavigationState {
	var toolbarSearchQuery: String = ""
	var isSearchPresented: Bool = false

	struct NavigationRequest: Equatable, Sendable {
		let targetTab: ResultsTab
		let targetNodeID: String
		let parentIDsToExpand: [String]
	}

	var navigationRequest: NavigationRequest?
}
