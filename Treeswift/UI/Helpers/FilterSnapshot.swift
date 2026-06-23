//
//  FilterSnapshot.swift
//  Treeswift
//
//  Value-type snapshot of FilterState for use off the main actor.
//

import Foundation
import PeripheryKit
import SourceGraph

/**
 An immutable, Sendable snapshot of FilterState captured on the main actor.
 Used to carry filter settings into background tasks without needing the MainActor-isolated FilterState.
 */
struct FilterSnapshot: Sendable {
	private let topLevelOnly: Bool
	private let showUnused: Bool
	private let showAssignOnly: Bool
	private let showRedundantProtocol: Bool
	private let showRedundantAccessControl: Bool
	private let showSuperfluousIgnoreCommand: Bool
	private let showClass: Bool
	private let showEnum: Bool
	private let showExtension: Bool
	private let showFunction: Bool
	private let showImport: Bool
	private let showInitializer: Bool
	private let showParameter: Bool
	private let showProperty: Bool
	private let showProtocol: Bool
	private let showStruct: Bool
	private let showTypealias: Bool

	init(from filterState: FilterState) {
		topLevelOnly = filterState.topLevelOnly
		showUnused = filterState.showUnused
		showAssignOnly = filterState.showAssignOnly
		showRedundantProtocol = filterState.showRedundantProtocol
		showRedundantAccessControl = filterState.showRedundantAccessControl
		showSuperfluousIgnoreCommand = filterState.showSuperfluousIgnoreCommand
		showClass = filterState.showClass
		showEnum = filterState.showEnum
		showExtension = filterState.showExtension
		showFunction = filterState.showFunction
		showImport = filterState.showImport
		showInitializer = filterState.showInitializer
		showParameter = filterState.showParameter
		showProperty = filterState.showProperty
		showProtocol = filterState.showProtocol
		showStruct = filterState.showStruct
		showTypealias = filterState.showTypealias
	}

	/** Returns true if the scan result should be shown given this filter snapshot. */
	nonisolated func shouldShow(scanResult: ScanResult, declaration: Declaration) -> Bool {
		if topLevelOnly, declaration.parent != nil {
			return false
		}
		return shouldShowIgnoringTopLevel(scanResult: scanResult, declaration: declaration)
	}

	private nonisolated func shouldShowIgnoringTopLevel(scanResult: ScanResult, declaration: Declaration) -> Bool {
		switch scanResult.annotation.warningType {
		case .unused where !showUnused: return false
		case .assignOnly where !showAssignOnly: return false
		case .redundantProtocol where !showRedundantProtocol: return false
		case .redundantAccessControl where !showRedundantAccessControl: return false
		case .superfluousIgnoreCommand where !showSuperfluousIgnoreCommand: return false
		default: break
		}

		let swiftType = SwiftType.from(declarationKind: declaration.kind)
		switch swiftType {
		case .class where !showClass: return false
		case .enum where !showEnum: return false
		case .extension where !showExtension: return false
		case .function where !showFunction: return false
		case .import where !showImport: return false
		case .initializer where !showInitializer: return false
		case .parameter where !showParameter: return false
		case .property where !showProperty: return false
		case .protocol where !showProtocol: return false
		case .struct where !showStruct: return false
		case .typealias where !showTypealias: return false
		default: break
		}

		return true
	}
}
