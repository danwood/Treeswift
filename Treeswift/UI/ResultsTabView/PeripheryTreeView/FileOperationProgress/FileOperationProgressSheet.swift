import SwiftUI

/* folderprivate */
struct FileOperationProgressSheet: View {
	let progressState: FileOperationProgressState
	let onCancel: () -> Void

	var body: some View {
		VStack(spacing: 16) {
			Text("Processing Files")
				.font(.headline)

			ProgressView(
				value: Double(progressState.processedCount),
				total: Double(progressState.totalCount)
			)
			.progressViewStyle(.linear)
			.frame(width: 300)

			Button("Stop") {
				onCancel()
			}
			.buttonStyle(.borderedProminent)
		}
		.padding(24)
		.frame(minWidth: 400)
	}
}
