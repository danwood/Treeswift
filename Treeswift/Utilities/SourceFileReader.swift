//
//  SourceFileReader.swift
//  Treeswift
//
//  Utility for reading source file content with caching
//

import Foundation

@MainActor
struct SourceFileReader {
	// Cache to avoid re-reading same files
	private static var cache: [String: [String]] = [:]
	private static let maxCacheSize = 50

	// Read a specific line from a file (1-indexed)
	static func readLine(
		from filePath: String,
		lineNumber: Int
	) -> String? {
		let lines = loadFile(at: filePath)

		guard lineNumber > 0, lineNumber <= lines.count else {
			return nil
		}

		return lines[lineNumber - 1]
	}

	/**
	 Invalidate the cache for a specific file.

	 Call this after modifying a file to ensure subsequent reads get fresh content.
	 */
	static func invalidateCache(for filePath: String) {
		cache.removeValue(forKey: filePath)
	}

	// Load entire file into array of lines (with caching)
	private static func loadFile(at path: String) -> [String] {
		if let cached = cache[path] {
			return cached
		}

		guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
			return []
		}

		let lines = content.components(separatedBy: .newlines)

		if cache.count >= maxCacheSize {
			cache.removeValue(forKey: cache.keys.first!)
		}
		cache[path] = lines

		return lines
	}
}
