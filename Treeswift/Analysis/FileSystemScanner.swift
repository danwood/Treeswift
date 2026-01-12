//
//  FileSystemScanner.swift
//  Treeswift
//
//  Scans file system for Swift source files and builds hierarchical tree
//

import Foundation

final class FileSystemScanner: Sendable {

	nonisolated init() {}

	nonisolated func scanProject(at projectPath: String) async throws -> [FileBrowserNode] {
		let projectURL = URL(fileURLWithPath: projectPath)
		let projectDir = projectURL.deletingLastPathComponent()

		let gitignorePatterns = loadGitignorePatterns(in: projectDir)

		let rootNode = try scanDirectory(
			at: projectDir,
			relativeTo: projectDir,
			gitignorePatterns: gitignorePatterns
		)

		switch rootNode {
		case .directory(let dir):
			return dir.children
		case .file:
			return []
		}
	}

	private nonisolated func loadGitignorePatterns(in directory: URL) -> [String] {
		let gitignoreURL = directory.appendingPathComponent(".gitignore")

		guard let content = try? String(contentsOf: gitignoreURL, encoding: .utf8) else {
			return []
		}

		return content
			.components(separatedBy: .newlines)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty && !$0.hasPrefix("#") }
	}

	private nonisolated func shouldIgnore(path _: String, relativePath: String, gitignorePatterns: [String]) -> Bool {
		let pathComponents = relativePath.components(separatedBy: "/")

		for component in pathComponents {
			if component.hasPrefix(".") {
				return true
			}
		}

		for pattern in gitignorePatterns {
			if matchesGitignorePattern(path: relativePath, pattern: pattern) {
				return true
			}
		}

		return false
	}

	private nonisolated func matchesGitignorePattern(path: String, pattern: String) -> Bool {
		if pattern.hasSuffix("/") {
			let dirPattern = String(pattern.dropLast())
			return path.hasPrefix(dirPattern + "/") || path == dirPattern
		}

		if pattern.contains("*") {
			let regexPattern = pattern
				.replacingOccurrences(of: ".", with: "\\.")
				.replacingOccurrences(of: "*", with: ".*")

			if let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$") {
				let range = NSRange(path.startIndex..<path.endIndex, in: path)
				return regex.firstMatch(in: path, range: range) != nil
			}
		}

		return path.hasPrefix(pattern + "/") || path == pattern || path.hasSuffix("/" + pattern)
	}

	private nonisolated func scanDirectory(
		at url: URL,
		relativeTo rootURL: URL,
		gitignorePatterns: [String]
	) throws -> FileBrowserNode {
		let fileManager = FileManager.default
		let relativePath = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")

		if shouldIgnore(path: url.path, relativePath: relativePath, gitignorePatterns: gitignorePatterns) {
			return .directory(FileBrowserDirectory(
				id: url.path,
				name: url.lastPathComponent,
				children: []
			))
		}

		let contents = try fileManager.contentsOfDirectory(
			at: url,
			includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
			options: [.skipsHiddenFiles]
		)

		var children: [FileBrowserNode] = []

		for itemURL in contents {
			let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
			let isDirectory = resourceValues.isDirectory ?? false

			let itemRelativePath = itemURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")

			if shouldIgnore(path: itemURL.path, relativePath: itemRelativePath, gitignorePatterns: gitignorePatterns) {
				continue
			}

			if isDirectory {
				let childNode = try scanDirectory(
					at: itemURL,
					relativeTo: rootURL,
					gitignorePatterns: gitignorePatterns
				)

				children.append(childNode)
			} else if itemURL.pathExtension == "swift" {
				let modificationDate = resourceValues.contentModificationDate
				let fileSize = resourceValues.fileSize.map { Int64($0) }

				children.append(.file(FileBrowserFile(
					id: itemURL.path,
					name: itemURL.lastPathComponent,
					path: itemURL.path,
					typeInfos: nil,
					modificationDate: modificationDate,
					fileSize: fileSize
				)))
			}
		}

		children.sort(by: { lhs, rhs in
			switch (lhs, rhs) {
			case (.directory(let lhsDir), .directory(let rhsDir)):
				return lhsDir.name.localizedStandardCompare(rhsDir.name) == .orderedAscending
			case (.file(let lhsFile), .file(let rhsFile)):
				return lhsFile.name.localizedStandardCompare(rhsFile.name) == .orderedAscending
			case (.directory, .file):
				return true
			case (.file, .directory):
				return false
			}
		})

		return .directory(FileBrowserDirectory(
			id: url.path,
			name: url.lastPathComponent,
			children: children
		))
	}
}
