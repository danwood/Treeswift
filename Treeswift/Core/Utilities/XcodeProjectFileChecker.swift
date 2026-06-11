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
/// Modern Xcode projects can also use **synchronized folder groups**
/// (`PBXFileSystemSynchronizedRootGroup`): the folder is scanned like a blue folder,
/// but individual files may be pinned via a `PBXFileSystemSynchronizedBuildFileExceptionSet`'s
/// `membershipExceptions` list (e.g. to change target membership). Those files are named
/// explicitly in project.pbxproj, so deleting them from disk breaks the build with
/// "Build input files cannot be found" — exactly like a yellow-group reference.
///
/// This checker reads project.pbxproj and returns false for any file that appears either
/// as an explicit PBXFileReference OR in a synchronized-group `membershipExceptions` list,
/// and true for files that don't appear (i.e. are discovered purely via folder reference).
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

	/// Returns the set of filenames that project.pbxproj names explicitly — both classic
	/// PBXFileReference entries and synchronized-group `membershipExceptions` — and which
	/// therefore must NOT be deleted from disk. Results are cached per xcodeproj path.
	private static func explicitFileReferences(in xcodeprojPath: String) -> Set<String> {
		if let cached = cache[xcodeprojPath] {
			return cached
		}
		let pbxprojPath = (xcodeprojPath as NSString).appendingPathComponent("project.pbxproj")
		guard let contents = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else {
			return []
		}
		let result = parseExplicitFileReferences(from: contents)
			.union(parseSynchronizedMembershipExceptions(from: contents))
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

	/// Parses filenames from every `PBXFileSystemSynchronizedBuildFileExceptionSet`'s
	/// `membershipExceptions` list. In a synchronized (blue) folder group these files are
	/// pinned individually in project.pbxproj (usually to alter target membership), so —
	/// like yellow-group references — Xcode requires them to exist on disk.
	///
	/// The exception lists look like:
	/// ```
	///     membershipExceptions = (
	///         Products/ProductType.swift,
	///         "Media/Release+Extensions.swift",
	///     );
	/// ```
	/// Entries may be bare or double-quoted and are paths relative to the folder; only the
	/// last path component is needed for the filename comparison in `isSafeToDelete`.
	private static func parseSynchronizedMembershipExceptions(from pbxproj: String) -> Set<String> {
		var filenames = Set<String>()
		var inExceptionList = false

		for line in pbxproj.split(separator: "\n", omittingEmptySubsequences: false) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)

			if !inExceptionList {
				if trimmed.hasPrefix("membershipExceptions = (") {
					inExceptionList = true
				}
				continue
			}

			// End of this exception list.
			if trimmed.hasPrefix(")") {
				inExceptionList = false
				continue
			}

			// Strip a trailing comma, then surrounding quotes, leaving a relative path.
			var entry = trimmed
			if entry.hasSuffix(",") {
				entry.removeLast()
			}
			if entry.hasPrefix("\""), entry.hasSuffix("\""), entry.count >= 2 {
				entry = String(entry.dropFirst().dropLast())
			}
			guard !entry.isEmpty else { continue }

			let filename = URL(fileURLWithPath: entry).lastPathComponent
			if filename.hasSuffix(".swift") {
				filenames.insert(filename)
			}
		}

		return filenames
	}

	/// Clears the cache. Call after modifying a project file.
	static func clearCache() {
		cache.removeAll()
	}
}
