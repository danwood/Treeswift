//
//  URLExtensions.swift
//  Treeswift
//
//  URL extensions for project file validation
//

import Foundation

extension URL {
	/// Returns true if this URL points to a valid Xcode project or Swift package file
	var isValidProjectFile: Bool {
		let ext = pathExtension
		return ext == "xcodeproj" || ext == "xcworkspace" ||
			lastPathComponent == "Package.swift"
	}

	/// Detects the project type from the URL
	var detectedProjectType: ProjectType? {
		if pathExtension == "xcodeproj" || pathExtension == "xcworkspace" {
			return .xcode
		}
		if lastPathComponent == "Package.swift" {
			return .swiftPackage
		}
		return nil
	}
}
