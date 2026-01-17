import SwiftUI

@MainActor
@Observable
final class FileOperationProgressState {
	var isProcessing: Bool = false
	var currentFile: String = ""
	var processedCount: Int = 0
	var totalCount: Int = 0
	var isCancelled: Bool = false

	func reset() {
		isProcessing = false
		currentFile = ""
		processedCount = 0
		totalCount = 0
		isCancelled = false
	}
}
