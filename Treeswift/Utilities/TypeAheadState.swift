//
//  TypeAheadState.swift
//  Treeswift
//
//  Manages the type-ahead search buffer for Finder-style keyboard search.
//  Accumulates typed characters and resets after a configurable pause.
//

import Foundation

@Observable
@MainActor
final class TypeAheadState {
	private(set) var typeBuffer: String = ""
	private var resetTask: Task<Void, Never>?
	private let resetDelay: Duration = .seconds(1.5)

	/**
	 Appends a character to the type-ahead buffer and triggers a search.
	 Resets the auto-clear timer on each keystroke. After resetDelay
	 seconds of inactivity, the buffer clears automatically.
	 */
	func appendCharacter(
		_ char: String,
		searchHandler: (String) -> Void
	) {
		resetTask?.cancel()
		typeBuffer += char
		searchHandler(typeBuffer)
		resetTask = Task {
			try? await Task.sleep(for: resetDelay)
			guard !Task.isCancelled else { return }
			typeBuffer = ""
		}
	}

	func clear() {
		resetTask?.cancel()
		typeBuffer = ""
	}
}
