//
//  PeripheryKit-extensions.swift
//  Treeswift
//
//  Created by Dan Wood on 12/11/25.
//

import PeripheryKit

extension ScanResult.Annotation {
	/**
	 Determines whether code can be removed for this annotation.

	 This method evaluates whether a declaration with this annotation can be safely removed
	 from source code based on the annotation type and available location information.
	 */
	func canRemoveCode(hasFullRange: Bool, isImport: Bool) -> Bool {
		switch self {
		case .unused:
			hasFullRange || isImport
		case .redundantPublicAccessibility,
		     .redundantInternalAccessibility,
		     .redundantFilePrivateAccessibility,
		     .redundantAccessibility:
			true
		case .assignOnlyProperty, .redundantProtocol:
			false
		case .superfluousIgnoreCommand:
			true // FIXME: We can try to remove, though it may not work if it's not positioned as expected
		}
	}
}

extension ScanResult.Annotation: @retroactive RawRepresentable {
	public typealias RawValue = Int

	// Map each annotation to a stable integer, ignoring any parameters/associated values
	public var rawValue: RawValue {
		switch self {
		case .unused: 0
		case .assignOnlyProperty: 1
		case .redundantProtocol: 2
		case .redundantPublicAccessibility: 3
		case .superfluousIgnoreCommand: 4
		case .redundantInternalAccessibility: 5
		case .redundantFilePrivateAccessibility: 6
		case .redundantAccessibility: 7
		}
	}

	// Decoding from a raw value is unsupported and should fail
	public init?(rawValue: RawValue) {
		nil
	}
}
