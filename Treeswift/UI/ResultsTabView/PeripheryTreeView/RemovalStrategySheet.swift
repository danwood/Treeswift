//
//  RemovalStrategySheet.swift
//  Treeswift
//
//  Presents removal strategy options before deleting unused code.
//

import AppKit
import Flow
import SwiftUI

// Semitransparent background colors for chain link pills
private let keepBackground = Color.green.opacity(0.12)
private let deleteBackground = Color.red.opacity(0.12)
private let pillCornerRadius: CGFloat = 4
private let hangingIndent: CGFloat = 10

/* folderprivate */ struct RemovalStrategySheet: View {
	let targetName: String
	let dependencyChains: [DependencyChain]
	let onConfirm: (RemovalStrategy) -> Void
	let onCancel: () -> Void

	@State private var selectedStrategy: RemovalStrategy = .skipReferenced
	@State private var detailsExpanded = false

	private static let strategies: [(strategy: RemovalStrategy, title: String, description: String)] = [
		(
			.skipReferenced,
			"Skip code still referenced by other unused code",
			"Only removes declarations with no remaining references. Guarantees the build won't break."
		),
		(
			.forceRemoveAll,
			"Remove all unused code (may prevent compilation)",
			"Removes everything flagged as unused, even if other unused code still references it."
		),
		(
			.cascade,
			"Cascade deletion to remove referencing unused code",
			"Also removes unused code in other files that references the deleted declarations."
		)
	]

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Remove Unused Code")
				.font(.headline)

			Text("Choose how to handle unused declarations that are referenced by other unused code:")
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)

			VStack(alignment: .leading, spacing: 12) {
				ForEach(Self.strategies, id: \.title) { item in
					strategyRow(item.strategy, title: item.title, description: item.description)
				}
			}

			if !dependencyChains.isEmpty {
				detailsSection
			}

			HStack {
				Spacer()
				Button("Cancel", action: onCancel)
					.keyboardShortcut(.cancelAction)
				Button("Remove") {
					onConfirm(selectedStrategy)
				}
				.keyboardShortcut(.defaultAction)
				.buttonStyle(.borderedProminent)
			}
		}
		.padding(24)
		.frame(width: 560)
	}

	// MARK: - Details Section

	private var detailsSection: some View {
		VStack(alignment: .leading, spacing: 0) {
			detailsHeader
			if detailsExpanded {
				ScrollView {
					VStack(alignment: .leading, spacing: 4) {
						ForEach(dependencyChains) { chain in
							chainRow(chain)
						}
					}
					.padding(.vertical, 4)
				}
				.frame(maxHeight: 200)
			}
		}
	}

	private var detailsHeader: some View {
		HStack(spacing: 6) {
			Image(systemName: detailsExpanded ? "chevron.down" : "chevron.right")
				.font(.caption)
				.foregroundStyle(.secondary)
			Text("Details")
				.font(.subheadline)
			if detailsExpanded {
				legendView
				Spacer()
				Button("Copy") {
					let markdown = dependencyChainsAsMarkdown()
					NSPasteboard.general.clearContents()
					NSPasteboard.general.setString(markdown, forType: .string)
				}
				.controlSize(.small)
			}
		}
		.contentShape(.rect)
		.onTapGesture {
			withAnimation {
				detailsExpanded.toggle()
			}
		}
	}

	private var legendView: some View {
		HStack(spacing: 6) {
			Text("Keeping")
				.font(.caption)
				.padding(.horizontal, 4)
				.padding(.vertical, 1)
				.background(keepBackground, in: .rect(cornerRadius: pillCornerRadius))
			Text("Deleting")
				.font(.caption)
				.strikethrough()
				.padding(.horizontal, 4)
				.padding(.vertical, 1)
				.background(deleteBackground, in: .rect(cornerRadius: pillCornerRadius))
			Text("In other files")
				.font(.caption)
				.italic()
				.foregroundStyle(.secondary)
				.padding(.horizontal, 4)
				.padding(.vertical, 1)
				.background(keepBackground, in: .rect(cornerRadius: pillCornerRadius))
		}
		.padding(.horizontal, 6)
		.padding(.vertical, 3)
		.overlay(
			RoundedRectangle(cornerRadius: 4)
				.stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
		)
	}

	// MARK: - Chain Rows

	private func chainRow(_ chain: DependencyChain) -> some View {
		// Hanging indent: pad the HFlow's leading edge, then outdent the first line
		// with a negative leading padding on the container
		HFlow(itemSpacing: 0, rowSpacing: 2) {
			ForEach(chain.links.enumerated().map(\.self), id: \.element.id) { index, link in
				if index > 0 {
					Text(" ◀ ")
						.font(.system(.caption, design: .monospaced))
						.foregroundStyle(.secondary)
				}
				chainLinkView(link)
			}
		}
		.padding(.leading, hangingIndent)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func chainLinkView(_ link: ChainLink) -> some View {
		let deleting = link.isStrikethrough(strategy: selectedStrategy)
		let background = deleting ? deleteBackground : keepBackground

		var text = Text(link.name)
		if deleting {
			text = text.strikethrough()
		}
		if !link.isInScope {
			text = text.italic().foregroundStyle(.secondary)
		}
		return text
			.font(.system(.caption, design: .monospaced))
			.padding(.horizontal, 3)
			.padding(.vertical, 1)
			.background(background, in: .rect(cornerRadius: pillCornerRadius))
			.simultaneousGesture(
				TapGesture(count: 2).onEnded {
					openFileInEditor(path: link.filePath, line: link.line)
				}
			)
	}

	// MARK: - Copy as Markdown

	private func dependencyChainsAsMarkdown() -> String {
		dependencyChains.map { chain in
			chain.links.enumerated().map { index, link in
				let separator = index > 0 ? " ◀ " : ""
				let deleting = link.isStrikethrough(strategy: selectedStrategy)
				var formatted = "`\(link.name)`"
				if !link.isInScope {
					formatted = "_\(formatted)_"
				}
				if deleting {
					formatted = "~~\(formatted)~~"
				}
				return separator + formatted
			}
			.joined()
		}
		.joined(separator: "  \n")
	}

	// MARK: - Strategy Rows

	private func strategyRow(
		_ strategy: RemovalStrategy,
		title: String,
		description: String
	) -> some View {
		HStack(alignment: .top, spacing: 8) {
			Image(systemName: selectedStrategy == strategy ? "largecircle.fill.circle" : "circle")
				.foregroundStyle(.tint)
				.font(.body)
				.padding(.top, 2)

			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.body)
				Text(description)
					.font(.caption)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.contentShape(.rect)
		.onTapGesture {
			selectedStrategy = strategy
		}
	}
}
