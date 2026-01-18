//
//  FilterBarView.swift
//  Treeswift
//
//  Filter controls for Periphery scan results
//

import AdaptiveGrid
import AppKit
import Flow
import PeripheryKit
import SourceGraph
import SwiftUI

private struct TypeFilterItem: Identifiable {
	let id: String
	let swiftType: SwiftType
	let label: String
	let binding: ReferenceWritableKeyPath<FilterState, Bool>
	let disableWhenTopLevel: Bool

	/**
	 Determines if this type filter should be disabled based on current filter state.
	 Checks both top-level constraint and warning-type constraints.
	 */
	func isDisabled(filterState: FilterState) -> Bool {
		if disableWhenTopLevel, filterState.topLevelOnly {
			return true
		}
		return !filterState.isTypeFilterEnabled(swiftType)
	}

	static let allItems: [TypeFilterItem] = [
		TypeFilterItem(
			id: "struct",
			swiftType: .struct,
			label: "Struct",
			binding: \.showStruct,
			disableWhenTopLevel: false
		),
		TypeFilterItem(
			id: "class",
			swiftType: .class,
			label: "Class",
			binding: \.showClass,
			disableWhenTopLevel: false
		),
		TypeFilterItem(id: "enum", swiftType: .enum, label: "Enum", binding: \.showEnum, disableWhenTopLevel: false),
		TypeFilterItem(
			id: "typealias",
			swiftType: .typealias,
			label: "Typealias",
			binding: \.showTypealias,
			disableWhenTopLevel: false
		),
		TypeFilterItem(
			id: "protocol",
			swiftType: .protocol,
			label: "Protocol",
			binding: \.showProtocol,
			disableWhenTopLevel: false
		),
		TypeFilterItem(
			id: "extension",
			swiftType: .extension,
			label: "Extension",
			binding: \.showExtension,
			disableWhenTopLevel: false
		),
		TypeFilterItem(
			id: "parameter",
			swiftType: .parameter,
			label: "Parameter",
			binding: \.showParameter,
			disableWhenTopLevel: true
		),
		TypeFilterItem(
			id: "property",
			swiftType: .property,
			label: "Property",
			binding: \.showProperty,
			disableWhenTopLevel: false
		),
		TypeFilterItem(
			id: "initializer",
			swiftType: .initializer,
			label: "Initializer",
			binding: \.showInitializer,
			disableWhenTopLevel: true
		),
		TypeFilterItem(
			id: "function",
			swiftType: .function,
			label: "Function",
			binding: \.showFunction,
			disableWhenTopLevel: false
		),
		TypeFilterItem(
			id: "imoport",
			swiftType: .import,
			label: "Import",
			binding: \.showImport,
			disableWhenTopLevel: false
		)
	]
}

struct FilterBarView: View {
	@Bindable var filterState: FilterState
	let scanResults: [ScanResult]

	private var annotationCounts: [String: Int] {
		var counts: [String: Int] = [:]
		for result in scanResults {
			let declaration = result.declaration

			// Apply top-level filter if enabled
			if filterState.topLevelOnly, declaration.parent != nil {
				continue
			}

			let annotation = result.annotation.stringValue
			counts[annotation, default: 0] += 1
		}
		return counts
	}

	private var typeCounts: [SwiftType: Int] {
		var counts: [SwiftType: Int] = [:]
		for result in scanResults {
			let declaration = result.declaration

			// Apply top-level filter if enabled
			if filterState.topLevelOnly, declaration.parent != nil {
				continue
			}

			let swiftType = SwiftType.from(declarationKind: declaration.kind)
			counts[swiftType, default: 0] += 1
		}
		return counts
	}

	private func setAllWarningFilters(to value: Bool) {
		filterState.showUnused = value
		filterState.showAssignOnly = value
		filterState.showRedundantProtocol = value
		filterState.showRedundantPublic = value
	}

	private func setAllTypeFilters(to value: Bool) {
		for item in TypeFilterItem.allItems {
			if !item.isDisabled(filterState: filterState) {
				filterState[keyPath: item.binding] = value
			}
		}
	}

	var body: some View {
		Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
			// Row 1: Top-level filter
			GridRow(alignment: .center) {
				Text("Scope:")
					.gridColumnAlignment(.trailing)

				HStack {
					Toggle("Top-level only", isOn: $filterState.topLevelOnly)
						.toggleStyle(.switch)
						.controlSize(.small)

					Text("Suggestion: turn this on for the initial pass")
						.italic()
						.foregroundStyle(Color.secondary)
				}
			}

			// Row 2: Annotation categories (with HFlow for wrapping)
			GridRow {
				Text("Warning:")
					.gridColumnAlignment(.trailing)

				HFlow(itemSpacing: 10, rowSpacing: 8) {
					OptionClickToggle(
						isEnabled: $filterState.showUnused,
						onOptionClick: setAllWarningFilters
					) {
						HStack(spacing: 4) {
							Text("Unused")
							Text("(\(annotationCounts[ScanResult.Annotation.unused.stringValue] ?? 0))")
								.foregroundStyle(.secondary)
						}
					}

					OptionClickToggle(
						isEnabled: $filterState.showAssignOnly,
						onOptionClick: setAllWarningFilters
					) {
						HStack(spacing: 4) {
							Text("Assign-only")
							Text("(\(annotationCounts[ScanResult.Annotation.assignOnlyProperty.stringValue] ?? 0))")
								.foregroundStyle(.secondary)
						}
					}

					OptionClickToggle(
						isEnabled: $filterState.showRedundantProtocol,
						onOptionClick: setAllWarningFilters
					) {
						HStack(spacing: 4) {
							Text("Redundant Protocol")
							Text(
								"(\(annotationCounts[ScanResult.Annotation.redundantProtocol(references: [], inherited: []).stringValue] ?? 0))"
							)
							.foregroundStyle(.secondary)
						}
					}

					OptionClickToggle(
						isEnabled: $filterState.showRedundantPublic,
						onOptionClick: setAllWarningFilters
					) {
						HStack(spacing: 4) {
							Text("Redundant Public")
							Text(
								"(\(annotationCounts[ScanResult.Annotation.redundantPublicAccessibility(modules: []).stringValue] ?? 0))"
							)
							.foregroundStyle(.secondary)
						}
					}

					OptionClickToggle(
						isEnabled: $filterState.showSuperfluousIgnoreCommand,
						onOptionClick: setAllWarningFilters
					) {
						HStack(spacing: 4) {
							Text("Superflous Ignore")
							Text(
								"(\(annotationCounts[ScanResult.Annotation.superfluousIgnoreCommand.stringValue] ?? 0))"
							)
							.foregroundStyle(.secondary)
						}
					}
				}
			}

			// Row 3: Swift types (with LazyVGrid for adaptive layout)
			GridRow {
				Text("Swift Type:")
					.gridColumnAlignment(.trailing)

				AdaptiveGrid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
					ForEach(TypeFilterItem.allItems) { item in
						let isDisabled = item.isDisabled(filterState: filterState)

						OptionClickToggle(
							isEnabled: $filterState[dynamicMember: item.binding],
							onOptionClick: setAllTypeFilters
						) {
							HStack(spacing: 6) {
								BadgeView(badge: Badge(
									letter: item.swiftType.rawValue,
									count: 1,
									swiftType: item.swiftType,
									isUnused: true
								))
								Text(item.label)
								Text("(\(typeCounts[item.swiftType] ?? 0))")
									.foregroundStyle(.secondary)
							}
						}
						.fixedSize()
						.disabled(isDisabled)
						.opacity(isDisabled ? 0.5 : 1.0)
					}
				}
			}
		}
		.padding(.vertical, 8)
	}
}
