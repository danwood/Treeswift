//
//  PathFormatter.swift
//  Treeswift
//
//  Utility for formatting file paths relative to project root
//

import Foundation

/// Formats a full path as relative to the project root, or falls back to tilde-abbreviated path
/// - Parameters:
///   - fullPath: The absolute file path to format
///   - projectRootPath: The project root directory (containing folder of the project file)
/// - Returns: Path relative to project root, or tilde-abbreviated path if not within project
nonisolated func relativePath(_ fullPath: String, to projectRootPath: String?) -> String {
	if let projectRoot = projectRootPath, fullPath.hasPrefix(projectRoot) {
		var relative = String(fullPath.dropFirst(projectRoot.count))
		// Remove leading slash if present
		if relative.hasPrefix("/") {
			relative = String(relative.dropFirst())
		}
		return relative
	}
	return (fullPath as NSString).abbreviatingWithTildeInPath
}

/// Derives the project root path from a project file path
/// - Parameter projectPath: Path to the project file (.xcodeproj, Package.swift, etc.)
/// - Returns: The containing directory path, or nil if projectPath is nil
func projectRootPath(from projectPath: String?) -> String? {
	projectPath.map { ($0 as NSString).deletingLastPathComponent }
}
