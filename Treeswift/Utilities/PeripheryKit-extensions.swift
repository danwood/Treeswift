//
//  PeripheryKit-extensions.swift
//  Treeswift
//
//  Created by Dan Wood on 12/11/25.
//

import PeripheryKit

extension ScanResult.Annotation {
	// Check if annotation is redundant public
	public var isRedundantPublic: Bool {
		if case .redundantPublicAccessibility = self { true } else { false }
	}

	// Check if annotation is redundant protocol
	public var isRedundantProtocol: Bool {
		if case .redundantProtocol = self { true } else { false }
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

	/**
	 Determines whether code can be removed for this annotation.

	 This method evaluates whether a declaration with this annotation can be safely removed
	 from source code based on the annotation type and available location information.
	 */
	func canRemoveCode(hasFullRange: Bool, isImport: Bool) -> Bool {
		switch self {
		case .unused:
			hasFullRange || isImport
		case .redundantPublicAccessibility:
			true
		case .assignOnlyProperty, .redundantProtocol:
			false
		case .superfluousIgnoreCommand:
			true
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
		nil
	}
}
