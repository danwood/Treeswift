import Foundation

/**
 Resolves a dropped or selected URL to a recognized project file URL and its type.

 Handles three cases:
 - A direct project file (.xcodeproj, .xcworkspace, Package.swift)
 - A folder containing a project file
 - An invalid or unrecognized URL (returns nil)
 */
enum ProjectURLResolver {
	struct ResolvedProject {
		let url: URL
		let projectType: ProjectType
	}

	static func resolve(from url: URL) -> ResolvedProject? {
		if url.isValidProjectFile {
			guard let projectType = url.detectedProjectType else { return nil }
			return ResolvedProject(url: url, projectType: projectType)
		}

		if url.hasDirectoryPath {
			return resolveFromDirectory(url)
		}

		return nil
	}

	private static func resolveFromDirectory(_ url: URL) -> ResolvedProject? {
		let fm = FileManager.default

		if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
		   let xcodeproj = contents.first(where: {
		   	$0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace"
		   }) {
			return ResolvedProject(url: xcodeproj, projectType: .xcode)
		}

		let packageSwift = url.appending(path: "Package.swift")
		if fm.fileExists(atPath: packageSwift.path) {
			return ResolvedProject(url: packageSwift, projectType: .swiftPackage)
		}

		return nil
	}
}
