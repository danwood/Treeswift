//
//  XcodeSchemeReader.swift
//  Treeswift
//
//  Reads available schemes from Xcode projects and workspaces
//

import Foundation

private nonisolated struct XcodeListOutput: Codable, Sendable {
	let project: ProjectDetails?
	let workspace: WorkspaceDetails?
}

private nonisolated struct ProjectDetails: Codable, Sendable {
	let schemes: [String]
}

private nonisolated struct WorkspaceDetails: Codable, Sendable {
	let schemes: [String]
}

class XcodeSchemeReader {

	/// Get cached schemes synchronously if available and valid
	/// - Parameter path: Full path to .xcodeproj or .xcworkspace
	/// - Returns: Cached schemes if valid, nil if cache miss or stale
	@MainActor
	static func cachedSchemes(forProjectAt path: String) -> [String]? {
		if let cachedSchemes = SchemeCache.shared.get(forPath: path) {
			return cachedSchemes
		}
		return nil
	}

	/// Query schemes from an Xcode project or workspace
	/// - Parameter path: Full path to .xcodeproj or .xcworkspace
	/// - Returns: Array of scheme names
	@MainActor
	static func schemes(forProjectAt path: String) async -> [String] {
		// Check cache first (validates modification date automatically)
		if let cachedSchemes = cachedSchemes(forProjectAt: path) {
			return cachedSchemes
		}

		// Cache miss or stale - query xcodebuild
		let schemes = await querySchemesFromXcodebuild(path: path)

		// Store in cache with current modification date
		SchemeCache.shared.set(schemes: schemes, forPath: path)

		return schemes
	}

	/// Query xcodebuild directly without cache
	/// - Parameter path: Full path to .xcodeproj or .xcworkspace
	/// - Returns: Array of scheme names
	private nonisolated static func querySchemesFromXcodebuild(path: String) async -> [String] {
		// Move Process execution to background thread to avoid blocking MainActor
		await Task.detached {
			let url = URL(fileURLWithPath: path)
			let pathExtension = url.pathExtension

			// Determine if it's a project or workspace
			let projectType: String
			if pathExtension == "xcodeproj" {
				projectType = "project"
			} else if pathExtension == "xcworkspace" {
				projectType = "workspace"
			} else {
				// Not a valid project/workspace file
				return []
			}

			// Run xcodebuild -list -json
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
			process.arguments = ["-\(projectType)", path, "-list", "-json"]

			let outputPipe = Pipe()
			let errorPipe = Pipe()
			process.standardOutput = outputPipe
			process.standardError = errorPipe

			do {
				try process.run()
				process.waitUntilExit()

				guard process.terminationStatus == 0 else {
					return []
				}

				let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
				let outputString = String(data: outputData, encoding: .utf8) ?? ""

				// xcodebuild may output warnings before JSON, find the JSON portion
				let lines = outputString.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
				guard let startIndex = lines.firstIndex(where: { $0 == "{" }) else {
					return []
				}

				var jsonLines = lines.suffix(from: startIndex)
				if let lastIndex = jsonLines.lastIndex(where: { $0 == "}" }) {
					jsonLines = jsonLines.prefix(upTo: lastIndex + 1)
				}

				let jsonString = jsonLines.joined(separator: "\n")
				guard let jsonData = jsonString.data(using: .utf8) else {
					return []
				}

				let output = try JSONDecoder().decode(XcodeListOutput.self, from: jsonData)

				// Extract schemes based on project type
				if projectType == "project" {
					return output.project?.schemes ?? []
				} else {
					return output.workspace?.schemes ?? []
				}
			} catch {
				print("Error reading schemes: \(error)")
				return []
			}
		}.value
	}
}
