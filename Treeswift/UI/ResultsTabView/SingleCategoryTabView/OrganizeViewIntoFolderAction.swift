//
//  OrganizeViewIntoFolderAction.swift
//  Treeswift
//
//  Context menu action to organize a view and its children into a dedicated folder
//

import SwiftUI
import AppKit

struct OrganizeViewIntoFolderAction: View {
	let declaration: DeclarationNode
	let projectRootPath: String?
	@Environment(\.undoManager) var undoManager
	@Environment(\.refreshFileTree) var refreshFileTree

	private var isView: Bool {
		declaration.isView
	}

	private var hasChildren: Bool {
		!declaration.children.isEmpty
	}

	// Check if the view file is already inside a folder with matching name
	private var isAlreadyOrganized: Bool {
		guard let relativePath = declaration.locationInfo.relativePath else { return false }
		let pathComponents = (relativePath as NSString)
		let fileName = pathComponents.lastPathComponent
		let fileNameWithoutExt = (fileName as NSString).deletingPathExtension
		let parentFolder = (pathComponents.deletingLastPathComponent as NSString).lastPathComponent
		return fileNameWithoutExt == parentFolder
	}

	private var canOrganize: Bool {
		isView && hasChildren && !isAlreadyOrganized
	}

	// Get the view name (folder name to create)
	private var viewName: String {
		guard let relativePath = declaration.locationInfo.relativePath else {
			return declaration.displayName
		}
		let fileName = (relativePath as NSString).lastPathComponent
		return (fileName as NSString).deletingPathExtension
	}

	// Collect all file/folder paths that would be moved
	private var itemsToMove: [OrganizeItem] {
		var items: [OrganizeItem] = []
		collectItemsToMove(from: declaration.children, into: &items)
		return items
	}

	var body: some View {
		if canOrganize {
			Button("Organize '\(viewName)' into Folder…") {
				showConfirmationDialog()
			}
		}
	}

	private func collectItemsToMove(from children: [CategoriesNode], into items: inout [OrganizeItem]) {
		for child in children {
			switch child {
			case .declaration(let decl):
				if let relativePath = decl.locationInfo.relativePath {
					// Check if this is already in its own folder
					let isFolder = decl.folderIndicator != nil
					if isFolder {
						// For folder items, get the folder path (parent of the file)
						let folderPath = (relativePath as NSString).deletingLastPathComponent
						if !items.contains(where: { $0.relativePath == folderPath }) {
							items.append(OrganizeItem(relativePath: folderPath, isFolder: true))
						}
					} else {
						if !items.contains(where: { $0.relativePath == relativePath }) {
							items.append(OrganizeItem(relativePath: relativePath, isFolder: false))
						}
					}
				}

			case .section, .syntheticRoot:
				break
			}
		}
	}

	private func showConfirmationDialog() {
		let items = itemsToMove
		let name = viewName

		let alert = NSAlert()
		alert.messageText = "Organize '\(name)' into Folder"
		alert.alertStyle = .informational
		alert.addButton(withTitle: "Organize")
		alert.addButton(withTitle: "Cancel")

		// Build the informative text with file list
		var infoText = "This will create a folder named '\(name)' and move the following items into it:\n\n"
		infoText += "•\u{00a0}\(name).swift (parent view)\n"
		for item in items {
			let itemName = (item.relativePath as NSString).lastPathComponent
			if item.isFolder {
				infoText += "•\u{00a0}\(itemName)/ (folder)\n"
			} else {
				infoText += "•\u{00a0}\(itemName)\n"
			}
		}
		alert.informativeText = infoText

		let response = alert.runModal()
		if response == .alertFirstButtonReturn {
			executeOrganization()
		}
	}

	private func executeOrganization() {
		guard let projectRoot = projectRootPath,
			  let relativePath = declaration.locationInfo.relativePath else {
			showErrorAlert(message: "Cannot determine project root path")
			return
		}

		let fullPath = (projectRoot as NSString).appendingPathComponent(relativePath)
		let parentDirectory = (fullPath as NSString).deletingLastPathComponent
		let newFolderPath = (parentDirectory as NSString).appendingPathComponent(viewName)

		do {
			try organizeViewIntoFolder(
				viewFilePath: fullPath,
				newFolderPath: newFolderPath,
				itemsToMove: itemsToMove.map { item in
					(projectRoot as NSString).appendingPathComponent(item.relativePath)
				},
				undoManager: undoManager
			)
			refreshFileTree?()
		} catch {
			showErrorAlert(message: error.localizedDescription)
		}
	}

	private func showErrorAlert(message: String) {
		let alert = NSAlert()
		alert.messageText = "Organization Failed"
		alert.informativeText = message
		alert.alertStyle = .warning
		alert.addButton(withTitle: "OK")
		alert.runModal()
	}
}

struct OrganizeItem: Identifiable, Equatable {
	let id = UUID()
	let relativePath: String
	let isFolder: Bool
}
