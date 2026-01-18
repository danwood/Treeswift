//
//  FileContentAnalyzer.swift
//  Treeswift
//
//  File analysis utility for determining if files should be deleted after unused code removal
//

import Foundation
import SourceGraph
import SystemPackage

enum FileContentAnalyzer {
	/**
	Determines whether a file should be deleted after unused code removal.

	Returns a tuple indicating:
	- shouldDelete: true if file should be moved to trash
	- shouldRemoveImports: true if file should be kept but imports removed

	Decision logic:
	1. If any non-import declarations remain → keep file as-is
	2. If no declarations remain but >5 meaningful comments → keep file, remove imports
	3. Otherwise → delete file
	*/
	static func shouldDeleteFile(
		filePath: String,
		modifiedContents: String,
		sourceGraph: SourceGraph,
		removedWarningIDs: [String]
	) -> (shouldDelete: Bool, shouldRemoveImports: Bool) {
		// Check for remaining non-import declarations
		if hasNonImportDeclarations(
			filePath: filePath,
			sourceGraph: sourceGraph,
			removedWarningIDs: removedWarningIDs
		) {
			// File has code, keep as-is
			return (false, false)
		}

		// Count meaningful comments (excluding copyright headers)
		let meaningfulComments = countMeaningfulComments(in: modifiedContents)

		if meaningfulComments > 5 {
			// Keep file for comments, but remove useless imports
			return (false, true)
		}

		// No code, few comments → delete file
		return (true, false)
	}

	/**
	Checks if the file has any non-import declarations remaining after removal.

	Uses SourceGraph to find all declarations in the file, excludes removed declarations,
	and checks if any remaining declarations are not imports (kind != .module).
	*/
	static func hasNonImportDeclarations(
		filePath: String,
		sourceGraph: SourceGraph,
		removedWarningIDs: [String]
	) -> Bool {
		// Extract USRs from removed warning IDs
		let removedUSRs = Set(removedWarningIDs.compactMap { warningID -> String? in
			let components = warningID.split(separator: ":")
			guard components.count >= 2 else { return nil }
			return String(components[1])
		})

		// Find all declarations in this file
		let fileDeclarations = sourceGraph.allDeclarations.filter { declaration in
			declaration.location.file.path.string == filePath
		}

		// Filter out removed declarations
		let remainingDeclarations = fileDeclarations.filter { declaration in
			!declaration.usrs.contains { usr in removedUSRs.contains(usr) }
		}

		// Check if any remaining declarations are not imports
		return remainingDeclarations.contains { declaration in
			declaration.kind != .module
		}
	}

	/**
	Counts meaningful comment lines in the file, excluding copyright headers.

	Copyright headers are comments that appear before the first import statement.
	*/
	static func countMeaningfulComments(in contents: String) -> Int {
		let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)

		// Find index of first import statement
		var firstImportIndex: Int?
		for (index, line) in lines.enumerated() {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.starts(with: "import ") {
				firstImportIndex = index
				break
			}
		}

		// Count comment lines after first import
		var commentCount = 0
		let startIndex = (firstImportIndex ?? -1) + 1

		for index in startIndex..<lines.count {
			let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

			// Check for single-line comment
			if trimmed.starts(with: "//") {
				commentCount += 1
				continue
			}

			// Check for multi-line comment start
			if trimmed.starts(with: "/*") {
				commentCount += 1
				// Count remaining lines of multi-line comment
				var currentIndex = index
				while currentIndex < lines.count {
					let commentLine = lines[currentIndex].trimmingCharacters(in: .whitespaces)
					if commentLine.contains("*/") {
						break
					}
					currentIndex += 1
					if currentIndex < lines.count {
						commentCount += 1
					}
				}
			}
		}

		return commentCount
	}

	/**
	Removes all import statements from file contents.

	Used when keeping a file only for its comments.
	*/
	static func removeImportStatements(from contents: String) -> String {
		let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
		var result: [Substring] = []

		for line in lines {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			// Skip lines that start with "import "
			if !trimmed.starts(with: "import ") {
				result.append(line)
			}
		}

		return result.joined(separator: "\n")
	}
}
