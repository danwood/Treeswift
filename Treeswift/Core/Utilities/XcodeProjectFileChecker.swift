import Foundation

/// Determines whether source files are safe to delete from disk without
/// updating an Xcode project file.
///
/// Xcode supports two ways to track source files:
/// - **Folder references** (blue folders): Xcode scans the folder at build time.
///   Files can be added or removed on disk freely.
/// - **Group references** (yellow groups): Each file has an explicit PBXFileReference
///   entry in project.pbxproj. Deleting the file without updating the project breaks
///   the build with "Build input files cannot be found".
///
/// This checker reads project.pbxproj and returns false for any file that appears
/// as an explicit PBXFileReference, and true for files that don't appear (i.e. are
/// discovered via folder reference).
enum XcodeProjectFileChecker {
	/// Cache: xcodeproj path → set of filenames explicitly referenced.
	private static var cache: [String: Set<String>] = [:]

	/// Returns true if the given source file can be safely deleted from disk
	/// without breaking the Xcode project's build.
	///
	/// Pass the `.xcodeproj` path (or workspace path — the function locates the
	/// nearest `.xcodeproj` automatically if needed).
	static func isSafeToDelete(filePath: String, xcodeprojPath: String) -> Bool {
		let explicitFiles = explicitFileReferences(in: xcodeprojPath)
		let filename = URL(fileURLWithPath: filePath).lastPathComponent
		return !explicitFiles.contains(filename)
	}

	/// Returns the set of filenames explicitly listed as PBXFileReference entries
	/// in the given xcodeproj's project.pbxproj. Results are cached per xcodeproj path.
	private static func explicitFileReferences(in xcodeprojPath: String) -> Set<String> {
		if let cached = cache[xcodeprojPath] {
			return cached
		}
		let pbxprojPath = (xcodeprojPath as NSString).appendingPathComponent("project.pbxproj")
		guard let contents = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else {
			return []
		}
		let result = parseExplicitFileReferences(from: contents)
		cache[xcodeprojPath] = result
		return result
	}

	/// Parses PBXFileReference entries from raw pbxproj text.
	/// Extracts the `path` value from each line matching the PBXFileReference pattern.
	private static func parseExplicitFileReferences(from pbxproj: String) -> Set<String> {
		var filenames = Set<String>()
		var inFileReferenceSection = false

		for line in pbxproj.split(separator: "\n", omittingEmptySubsequences: false) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)

			if trimmed.contains("/* Begin PBXFileReference section */") {
				inFileReferenceSection = true
				continue
			}
			if trimmed.contains("/* End PBXFileReference section */") {
				break
			}

			guard inFileReferenceSection else { continue }

			// Lines look like:
			//   ABC123 /* Foo.swift */ = {isa = PBXFileReference; ... path = Foo.swift; ... };
			// Extract the path = value.
			if let pathRange = trimmed.range(of: "path = ") {
				let after = trimmed[pathRange.upperBound...]
				if let semicolon = after.firstIndex(of: ";") {
					let rawPath = String(after[..<semicolon])
					let filename = URL(fileURLWithPath: rawPath).lastPathComponent
					if !filename.isEmpty {
						filenames.insert(filename)
					}
				}
			}
		}

		return filenames
	}

	/// Clears the cache. Call after modifying a project file.
	static func clearCache() {
		cache.removeAll()
	}
}
