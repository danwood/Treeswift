//
//  XcodeDestinationReader.swift
//  Treeswift
//
//  Reads available build destinations from Xcode projects and workspaces
//

import Foundation

struct BuildDestination: Identifiable, Hashable, Sendable {
	var id: String { destinationString }
	let platform: String // e.g. "macOS", "iOS", "iOS Simulator"
	let destinationString: String // e.g. "generic/platform=iOS Simulator"
}

class XcodeDestinationReader {
	/// Query available build destinations for a scheme in an Xcode project or workspace
	/// - Parameters:
	///   - path: Full path to .xcodeproj or .xcworkspace
	///   - scheme: The scheme name to query destinations for
	/// - Returns: Array of unique platform destinations
	nonisolated static func destinations(forProjectAt path: String, scheme: String) async -> [BuildDestination] {
		await Task.detached {
			let url = URL(fileURLWithPath: path)
			let pathExtension = url.pathExtension

			let projectType: String
			if pathExtension == "xcodeproj" {
				projectType = "project"
			} else if pathExtension == "xcworkspace" {
				projectType = "workspace"
			} else {
				return []
			}

			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
			process.arguments = ["-\(projectType)", path, "-scheme", scheme, "-showdestinations"]

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

				return parseDestinations(from: outputString)
			} catch {
				print("Error reading destinations: \(error)")
				return []
			}
		}.value
	}

	/**
	 Parses xcodebuild -showDestinations output to extract unique platform destinations.
	 Each output line looks like: `{ platform:macOS, arch:arm64, id:..., name:My Mac }`
	 We extract unique platform values and map them to generic destination strings.
	 */
	private nonisolated static func parseDestinations(from output: String) -> [BuildDestination] {
		var seenPlatforms = Set<String>()
		var destinations: [BuildDestination] = []

		for line in output.split(separator: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { continue }

			// Extract platform value from "platform:VALUE" in the destination line
			let contents = trimmed.dropFirst().dropLast()
			let components = contents.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

			for component in components {
				let parts = component.split(separator: ":", maxSplits: 1)
				if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "platform" {
					let platform = parts[1].trimmingCharacters(in: .whitespaces)
					if seenPlatforms.insert(platform).inserted {
						destinations.append(BuildDestination(
							platform: platform,
							destinationString: "generic/platform=\(platform)"
						))
					}
					break
				}
			}
		}

		return destinations
	}
}
