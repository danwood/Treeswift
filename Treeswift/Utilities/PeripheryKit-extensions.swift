//
//  PeripheryKit-extensions.swift
//  Treeswift
//
//  Created by Dan Wood on 12/11/25.
//

import PeripheryKit

extension ScanResult.Annotation {

	var isUnused: Bool {
		switch self {
		case .unused: true
		default: false
		}
	}

	/**
	 Returns the string representation of this annotation.

	 IMPORTANT: This duplicates the logic from OutputFormatter.describe(_:) in
	 .../PeripheryKit/Results/OutputFormatter.swift:25-36

	 We replicate it here because OutputFormatter.describe() is a protocol extension method
	 that requires a conforming instance to call. These string values MUST match exactly.

	 If Periphery's OutputFormatter.describe() changes, update this to match.
	 */
	var stringValue: String {
		switch self {
		case .unused: "unused"
		case .assignOnlyProperty: "assignOnlyProperty"
		case .redundantProtocol: "redundantProtocol"
		case .redundantPublicAccessibility: "redundantPublicAccessibility"
		case .superfluousIgnoreCommand: "superfluousIgnoreCommand"
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
		}
	}


	// Decoding from a raw value is unsupported and should fail
	public init?(rawValue: RawValue) {
		return nil
	}
}
