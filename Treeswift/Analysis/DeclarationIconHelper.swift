//
//  DeclarationIconHelper.swift
//  Treeswift
//
//  Shared utilities for determining declaration icons
//

import Foundation
import SourceGraph

enum DeclarationIconHelper {
	nonisolated static func typeIcon(for declaration: Declaration) -> TreeIcon {
		if isMainApp(declaration) {
			.emoji("🔷")
		} else if conformsToView(declaration) {
			.emoji("🖼️")
		} else if declaration.kind == .class,
		          declaration.immediateInheritedTypeReferences.contains(where: { $0.name?.hasPrefix("NS") == true }) {
			.emoji("🟤")
		} else {
			.emoji(declaration.kind.icon)
		}
	}

	nonisolated static func conformsToView(_ declaration: Declaration) -> Bool {
		let hardcodedViewTypes: Set<String> = [
			"View",
			"ViewModifier",
			"DynamicViewContent",
			"ShapeView",
			"Shape",
			"NSViewControllerRepresentable",
			"NSViewRepresentable",
			"UIViewRepresentable",
			"UIViewControllerRepresentable",
			"WKInterfaceObjectRepresentable"
		]

		let hasViewConformance = declaration.immediateInheritedTypeReferences.contains(where: { ref in
			if let n = ref.name {
				let isViewType = hardcodedViewTypes.contains(n)
				return isViewType
			}
			return false
		})

		return hasViewConformance
	}

	nonisolated static func isMainApp(_ declaration: Declaration) -> Bool {
		if declaration.attributes.map(\.description).contains("main"),
		   declaration.immediateInheritedTypeReferences.contains(where: { $0.name?.contains("App") == true }) {
			return true
		}

		if let name = declaration.name, name.hasSuffix("App"),
		   declaration.immediateInheritedTypeReferences.contains(where: { $0.name?.contains("App") == true }) {
			return true
		}

		return false
	}
}
