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
		guard let symbolName = name else { return false }
		return symbolName.starts(with: "$s") || symbolName.contains("PreviewRegistryfMu_")
	}
}

extension Declaration.Kind {
	/// Returns the appropriate icon for this declaration kind.
	nonisolated var icon: String {
		switch self {
		case .struct: return "🟦"
		case .class: return "🔵"
		case .enum: return "🚦"
		case .protocol: return "📜"
		case .extensionStruct, .extensionClass, .extensionEnum, .extensionProtocol, .extension: return "🧩"
		case .typealias: return "🏷️"
		case .macro: return "🔮"
		case .precedenceGroup: return "⚖️"
		default:
			if self.rawValue.hasPrefix("function") {
				return "⚡️"
			} else if self.rawValue.hasPrefix("var") {
				return "📦"
			} else {
				return "⬜️"
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
