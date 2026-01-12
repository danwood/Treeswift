//
//  PeripheryIgnoreCommentInserter.swift
//  Treeswift
//
//  Utility for inserting periphery:ignore:all comments into Swift source files
//

import Foundation

struct PeripheryIgnoreCommentInserter {

	enum InsertionError: Error {
		case readFailed
		case writeFailed
	}

	/**
	Inserts a `// periphery:ignore:all` comment at the appropriate location in a Swift file.

	The comment is placed using this priority order:
	1. On a new line just before the first import statement
	2. If no imports, at the first run of multiple line feeds with spacing
	3. If neither, above the first non-comment, non-whitespace line
	4. Fallback: at the very beginning of the file
	*/
	static func insertIgnoreAllComment(at filePath: String) throws -> (original: String, modified: String) {
		// Read original contents
		guard let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
			throw InsertionError.readFailed
		}

		// Find insertion point and create modified contents
		let modifiedContents = insertComment(in: originalContents)

		// Write modified contents back to file
		do {
			try modifiedContents.write(toFile: filePath, atomically: true, encoding: .utf8)
		} catch {
			throw InsertionError.writeFailed
		}

		return (original: originalContents, modified: modifiedContents)
	}

	/**
	Determines the appropriate location to insert the ignore comment and returns modified contents.
	*/
	private static func insertComment(in content: String) -> String {
		let lines = content.components(separatedBy: .newlines)

		// Priority 1: Before first import statement
		if let importIndex = findFirstImportLine(in: lines) {
			return insertBeforeLine(importIndex, in: lines)
		}

		// Priority 2: At first run of multiple line feeds
		if let multiLineIndex = findFirstMultipleLineFeeds(in: lines) {
			return insertAtMultipleLineFeeds(multiLineIndex, in: lines)
		}

		// Priority 3: Above first line of code (non-comment, non-whitespace)
		if let codeIndex = findFirstCodeLine(in: lines) {
			return insertBeforeLine(codeIndex, in: lines)
		}

		// Fallback: Insert at beginning
		return insertAtBeginning(in: lines)
	}

	/**
	Finds the index of the first import statement.
	*/
	private static func findFirstImportLine(in lines: [String]) -> Int? {
		for (index, line) in lines.enumerated() {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("import ") {
				return index
			}
		}
		return nil
	}

	/**
	Finds the first occurrence of multiple consecutive empty lines.
	*/
	private static func findFirstMultipleLineFeeds(in lines: [String]) -> Int? {
		var consecutiveEmpty = 0

		for (index, line) in lines.enumerated() {
			if line.trimmingCharacters(in: .whitespaces).isEmpty {
				consecutiveEmpty += 1
				if consecutiveEmpty >= 2 {
					// Return the index of the first empty line in the run
					return index - consecutiveEmpty + 1
				}
			} else {
				consecutiveEmpty = 0
			}
		}
		return nil
	}

	/**
	Finds the first line that is actual code (not a comment, not whitespace).
	*/
	private static func findFirstCodeLine(in lines: [String]) -> Int? {
		var inMultilineComment = false

		for (index, line) in lines.enumerated() {
			let trimmed = line.trimmingCharacters(in: .whitespaces)

			// Skip empty lines
			if trimmed.isEmpty {
				continue
			}

			// Handle multi-line comment start
			if trimmed.hasPrefix("/*") {
				inMultilineComment = true
				// Check if comment also ends on same line
				if trimmed.contains("*/") {
					inMultilineComment = false
				}
				continue
			}

			// Handle multi-line comment end
			if inMultilineComment {
				if trimmed.contains("*/") {
					inMultilineComment = false
				}
				continue
			}

			// Skip single-line comments
			if trimmed.hasPrefix("//") {
				continue
			}

			// Found first line of actual code
			return index
		}

		return nil
	}

	/**
	Inserts the ignore comment before the specified line index.
	*/
	private static func insertBeforeLine(_ index: Int, in lines: [String]) -> String {
		var modifiedLines = lines
		modifiedLines.insert("// periphery:ignore:all", at: index)
		return modifiedLines.joined(separator: "\n")
	}

	/**
	Inserts the ignore comment at a run of multiple line feeds with proper spacing.
	*/
	private static func insertAtMultipleLineFeeds(_ index: Int, in lines: [String]) -> String {
		var modifiedLines = lines
		// Insert with blank line above and below
		modifiedLines.insert("", at: index)
		modifiedLines.insert("// periphery:ignore:all", at: index)
		modifiedLines.insert("", at: index)
		return modifiedLines.joined(separator: "\n")
	}

	/**
	Inserts the ignore comment at the very beginning of the file.
	*/
	private static func insertAtBeginning(in lines: [String]) -> String {
		var modifiedLines = lines
		// Insert comment at beginning with a blank line after
		modifiedLines.insert("", at: 0)
		modifiedLines.insert("// periphery:ignore:all", at: 0)
		return modifiedLines.joined(separator: "\n")
	}
}
