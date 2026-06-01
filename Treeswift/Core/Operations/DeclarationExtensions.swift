//
//  DeclarationExtensions.swift
//  Treeswift
//
//  Created by Dan Wood on 11/19/25.
//

import Foundation
import SourceGraph

extension Declaration {
	/// Returns true if this declaration is a compiler-generated preview symbol
	nonisolated var isPreviewSymbol: Bool {
		name.starts(with: "$s") || name.contains("PreviewRegistryfMu_")
	}
}

extension Declaration.Kind {
	/// Returns the appropriate icon for this declaration kind.
	nonisolated var icon: String {
		switch self {
		case .struct: "🟦"
		case .class: "🔵"
		case .enum: "🚦"
		case .protocol: "📜"
		case .extensionStruct, .extensionClass, .extensionEnum, .extensionProtocol, .extension: "🧩"
		case .typealias: "🏷️"
		case .macro: "🔮"
		case .precedenceGroup: "⚖️"
		default:
			if rawValue.hasPrefix("function") {
				"⚡️"
			} else if rawValue.hasPrefix("var") {
				"📦"
			} else {
				"⬜️"
			}
		}
	}

	/// Returns true if this kind represents a type (class, struct, enum, protocol)
	nonisolated var isTypeKind: Bool {
		switch self {
		case .class, .struct, .enum, .protocol,
		     .extensionClass, .extensionStruct, .extensionEnum, .extensionProtocol, .extension:
			true
		default:
			false
		}
	}
}
