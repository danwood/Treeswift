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
	let topLevelOnly: Bool
	let showUnused: Bool
	let showAssignOnly: Bool
	let showRedundantProtocol: Bool
	let showRedundantAccessControl: Bool
	let showSuperfluousIgnoreCommand: Bool
	let showClass: Bool
	let showEnum: Bool
	let showExtension: Bool
	let showFunction: Bool
	let showImport: Bool
	let showInitializer: Bool
	let showParameter: Bool
	let showProperty: Bool
	let showProtocol: Bool
	let showStruct: Bool
	let showTypealias: Bool

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
	func shouldShow(scanResult: ScanResult, declaration: Declaration) -> Bool {
		if topLevelOnly, declaration.parent != nil {
			return false
		}
		return shouldShowIgnoringTopLevel(scanResult: scanResult, declaration: declaration)
	}

	private func shouldShowIgnoringTopLevel(scanResult: ScanResult, declaration: Declaration) -> Bool {
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
