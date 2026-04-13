//
//  SwiftType.swift
//  Treeswift
//
//  Swift type classification with color mapping
//

import AppKit
import Foundation
import SourceGraph

enum SwiftType: String, CaseIterable, Sendable {
	case `class` = "C"
	case `enum` = "E"
	case `extension` = "X"
	case function = "F"
	case initializer = "I"
	case parameter = "A"
	case property = "P"
	case `protocol` = "R"
	case `struct` = "S"
	case `typealias` = "T"
	case `import` = "M"

	var color: NSColor {
		switch self {
		case .class: NSColor.systemOrange
		case .enum: NSColor.systemYellow.darker(by: 0.1)
		case .extension: NSColor.systemGray
		case .function: NSColor.systemGreen
		case .initializer: NSColor.systemGreen.darker()
		case .parameter: NSColor.systemTeal
		case .property: NSColor.systemBlue
		case .protocol: NSColor.systemPurple
		case .struct: NSColor.systemRed
		case .typealias: NSColor.systemBrown.lighter(by: 0.2)
		case .import: NSColor.lightGray
		}
	}

	nonisolated static func from(declarationKind: Declaration.Kind) -> SwiftType {
		switch declarationKind {
		case .class:
			.class
		case .enum, .enumelement:
			.enum
		case .extension, .extensionClass, .extensionEnum, .extensionProtocol, .extensionStruct:
			.extension
		case .functionConstructor, .functionDestructor:
			.initializer
		case .varParameter:
			.parameter
		case .varInstance, .varClass, .varStatic, .varGlobal, .varLocal:
			.property
		case .protocol:
			.protocol
		case .struct:
			.struct
		case .typealias:
			.typealias
		case .module:
			.import
		default:
			.function
		}
	}
}
