//
//  EditorOpener.swift
//  Treeswift
//
//  Utility for opening files in Xcode or default editor
//

import Foundation
import AppKit

/// Opens a file in Xcode (xed) at an optional line number, with fallback to system default
func openFileInEditor(path: String, line: Int? = nil) {
	let xedPath = "/usr/bin/xed"
	let fileManager = FileManager.default

	if fileManager.fileExists(atPath: xedPath) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: xedPath)

		if let line = line {
			process.arguments = ["--line", "\(line)", path]
		} else {
			process.arguments = [path]
		}

		do {
			try process.run()
		} catch {
			openFileInDefaultApp(path: path)
		}
	} else {
		openFileInDefaultApp(path: path)
	}
}

/// Opens a folder in Finder
func openFolderInFinder(path: String) {
	NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
}

/// Fallback: opens file with system default application
private func openFileInDefaultApp(path: String) {
	let url = URL(fileURLWithPath: path)
	NSWorkspace.shared.open(url)
}
