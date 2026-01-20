//
//  FilterState.swift
//  Treeswift
//
//  Manages filter state for Periphery results display
//

import Foundation
import PeripheryKit
import SourceGraph

@Observable
final class FilterState {
	private static let defaults = UserDefaults.standard

	// Change counter - increments whenever any filter changes
	var filterChangeCounter: Int = 0

	// Top-level filter
	var topLevelOnly: Bool = true {
		didSet {
			Self.defaults.set(topLevelOnly, forKey: "filterState.topLevelOnly")
			filterChangeCounter += 1
		}
	}

	// Annotation category filters
	var showUnused: Bool = true {
		didSet {
			Self.defaults.set(showUnused, forKey: "filterState.showUnused")
			filterChangeCounter += 1
		}
	}

	var showAssignOnly: Bool = true {
		didSet {
			Self.defaults.set(showAssignOnly, forKey: "filterState.showAssignOnly")
			filterChangeCounter += 1
		}
	}

	var showRedundantProtocol: Bool = true {
		didSet {
			Self.defaults.set(showRedundantProtocol, forKey: "filterState.showRedundantProtocol")
			filterChangeCounter += 1
		}
	}

	var showRedundantPublic: Bool = true {
		didSet {
			Self.defaults.set(showRedundantPublic, forKey: "filterState.showRedundantPublic")
			filterChangeCounter += 1
		}
	}

	var showSuperfluousIgnoreCommand: Bool = true {
		didSet {
			Self.defaults.set(showSuperfluousIgnoreCommand, forKey: "filterState.showSuperfluousIgnoreCommand")
			filterChangeCounter += 1
		}
	}

	// Swift type filters
	var showClass: Bool = true {
		didSet {
			Self.defaults.set(showClass, forKey: "filterState.showClass")
			filterChangeCounter += 1
		}
	}

	var showEnum: Bool = true {
		didSet {
			Self.defaults.set(showEnum, forKey: "filterState.showEnum")
			filterChangeCounter += 1
		}
	}

	var showExtension: Bool = true {
		didSet {
			Self.defaults.set(showExtension, forKey: "filterState.showExtension")
			filterChangeCounter += 1
		}
	}

	var showFunction: Bool = true {
		didSet {
			Self.defaults.set(showFunction, forKey: "filterState.showFunction")
			filterChangeCounter += 1
		}
	}

	var showImport: Bool = true {
		didSet {
			Self.defaults.set(showImport, forKey: "filterState.showImport")
			filterChangeCounter += 1
		}
	}

	var showInitializer: Bool = true {
		didSet {
			Self.defaults.set(showInitializer, forKey: "filterState.showInitializer")
			filterChangeCounter += 1
		}
	}

	var showParameter: Bool = true {
		didSet {
			Self.defaults.set(showParameter, forKey: "filterState.showParameter")
			filterChangeCounter += 1
		}
	}

	var showProperty: Bool = true {
		didSet {
			Self.defaults.set(showProperty, forKey: "filterState.showProperty")
			filterChangeCounter += 1
		}
	}

	var showProtocol: Bool = true {
		didSet {
			Self.defaults.set(showProtocol, forKey: "filterState.showProtocol")
			filterChangeCounter += 1
		}
	}

	var showStruct: Bool = true {
		didSet {
			Self.defaults.set(showStruct, forKey: "filterState.showStruct")
			filterChangeCounter += 1
		}
	}

	var showTypealias: Bool = true {
		didSet {
			Self.defaults.set(showTypealias, forKey: "filterState.showTypealias")
			filterChangeCounter += 1
		}
	}

	init() {
		loadFromDefaults()
	}

	private func loadFromDefaults() {
		let defaults = Self.defaults

		// Only load if key exists (preserves default true values on first launch)
		if defaults.object(forKey: "filterState.topLevelOnly") != nil {
			topLevelOnly = defaults.bool(forKey: "filterState.topLevelOnly")
		}
		if defaults.object(forKey: "filterState.showUnused") != nil {
			showUnused = defaults.bool(forKey: "filterState.showUnused")
		}
		if defaults.object(forKey: "filterState.showAssignOnly") != nil {
			showAssignOnly = defaults.bool(forKey: "filterState.showAssignOnly")
		}
		if defaults.object(forKey: "filterState.showRedundantProtocol") != nil {
			showRedundantProtocol = defaults.bool(forKey: "filterState.showRedundantProtocol")
		}
		if defaults.object(forKey: "filterState.showRedundantPublic") != nil {
			showRedundantPublic = defaults.bool(forKey: "filterState.showRedundantPublic")
		}
		if defaults.object(forKey: "filterState.showClass") != nil {
			showClass = defaults.bool(forKey: "filterState.showClass")
		}
		if defaults.object(forKey: "filterState.showEnum") != nil {
			showEnum = defaults.bool(forKey: "filterState.showEnum")
		}
		if defaults.object(forKey: "filterState.showExtension") != nil {
			showExtension = defaults.bool(forKey: "filterState.showExtension")
		}
		if defaults.object(forKey: "filterState.showFunction") != nil {
			showFunction = defaults.bool(forKey: "filterState.showFunction")
		}
		if defaults.object(forKey: "filterState.showInitializer") != nil {
			showInitializer = defaults.bool(forKey: "filterState.showInitializer")
		}
		if defaults.object(forKey: "filterState.showParameter") != nil {
			showParameter = defaults.bool(forKey: "filterState.showParameter")
		}
		if defaults.object(forKey: "filterState.showProperty") != nil {
			showProperty = defaults.bool(forKey: "filterState.showProperty")
		}
		if defaults.object(forKey: "filterState.showProtocol") != nil {
			showProtocol = defaults.bool(forKey: "filterState.showProtocol")
		}
		if defaults.object(forKey: "filterState.showStruct") != nil {
			showStruct = defaults.bool(forKey: "filterState.showStruct")
		}
		if defaults.object(forKey: "filterState.showTypealias") != nil {
			showTypealias = defaults.bool(forKey: "filterState.showTypealias")
		}
	}

	private let annotationFilterMap: [String: WritableKeyPath<FilterState, Bool>] = [
		ScanResult.Annotation.unused.stringValue: \.showUnused,
		ScanResult.Annotation.assignOnlyProperty.stringValue: \.showAssignOnly,
		ScanResult.Annotation.redundantProtocol(references: [], inherited: []).stringValue: \.showRedundantProtocol,
		ScanResult.Annotation.redundantPublicAccessibility(modules: []).stringValue: \.showRedundantPublic,
		ScanResult.Annotation.superfluousIgnoreCommand.stringValue: \.showSuperfluousIgnoreCommand
	]

	private let typeFilterMap: [SwiftType: WritableKeyPath<FilterState, Bool>] = [
		.class: \.showClass,
		.enum: \.showEnum,
		.extension: \.showExtension,
		.function: \.showFunction,
		.initializer: \.showInitializer,
		.parameter: \.showParameter,
		.property: \.showProperty,
		.protocol: \.showProtocol,
		.struct: \.showStruct,
		.typealias: \.showTypealias
	]

	// Generally tracks ScanResult.Annotation but may be consolidated or simplified
	enum WarningType {
		case unused
		case assignOnly
		case redundantProtocol
		case redundantPublic
		case superfluousIgnoreCommand
	}

	/**
	 Returns the set of warning types that can apply to a given Swift type.
	 Used to determine which type filters should be enabled based on selected warning filters.
	 */
	static func applicableWarnings(for swiftType: SwiftType) -> Set<WarningType> {
		switch swiftType {
		case .property:
			[.unused, .assignOnly, .redundantPublic]
		case .protocol:
			[.unused, .redundantProtocol, .redundantPublic]
		case .class, .struct, .enum, .typealias, .function, .initializer:
			[.unused, .redundantPublic]
		case .extension:
			[.unused, .redundantPublic]
		case .parameter:
			[.unused]
		case .import:
			[.unused]
		}
	}

	/**
	 Determines if a Swift type filter should be enabled based on current warning filter selection.
	 A type filter is enabled if at least one applicable warning type is enabled.
	 */
	func isTypeFilterEnabled(_ swiftType: SwiftType) -> Bool {
		let applicableWarnings = Self.applicableWarnings(for: swiftType)

		for warning in applicableWarnings {
			switch warning {
			case .unused where showUnused: return true
			case .assignOnly where showAssignOnly: return true
			case .redundantProtocol where showRedundantProtocol: return true
			case .redundantPublic where showRedundantPublic: return true
			default: continue
			}
		}

		return false
	}

	/// Check if a warning should be shown based on current filter settings
	func shouldShow(scanResult: ScanResult, declaration: Declaration) -> Bool {
		// Check top-level filter
		if topLevelOnly, declaration.parent != nil {
			return false
		}

		// Check annotation filter
		let annotationString = scanResult.annotation.stringValue
		if let keyPath = annotationFilterMap[annotationString] {
			if !self[keyPath: keyPath] {
				return false
			}
		}

		// Check SwiftType filter
		let swiftType = SwiftType.from(declarationKind: declaration.kind)
		if let keyPath = typeFilterMap[swiftType] {
			return self[keyPath: keyPath]
		}

		return true // Unknown annotations/types always shown
	}
}
