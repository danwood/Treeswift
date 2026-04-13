//
//  PeripheryKit-extensions.swift
//  Treeswift
//
//  Created by Dan Wood on 12/11/25.
//

import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

extension ScanResult.Annotation {
	/**
	 Determines whether code can be removed for this annotation.

	 This method evaluates whether a declaration with this annotation can be safely removed
	 from source code based on the annotation type and available location information.
	 */
	func canRemoveCode(hasFullRange: Bool, isImport: Bool, location: Location? = nil) -> Bool {
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
			// Validate that the comment can actually be found
			if let location {
				Self.canFindIgnoreComment(at: location)
			} else {
				// If no location provided, assume it can be removed (backward compatibility)
				true
			}
		}
	}

	/**
	 Checks if a periphery:ignore comment can be found near the specified location.

	 Searches backward up to 10 lines from the declaration to find the comment.
	 This prevents attempting to remove comments that don't exist or are too far away.
	 */
	private static func canFindIgnoreComment(at location: Location) -> Bool {
		let filePath = location.file.path.string
		guard let fileContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			return false
		}

		let lines = fileContents.components(separatedBy: .newlines)
		return CommentScanner.findCommentContaining(
			pattern: "periphery:ignore",
			in: lines,
			backwardFrom: location.line,
			maxDistance: 10
		) != nil
	}
}

// This will make it equatable (at least for the values that don't have parameters)
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
