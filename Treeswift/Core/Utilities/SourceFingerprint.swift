//
//  SourceFingerprint.swift
//  Treeswift
//
//  Computes a fast fingerprint of Swift source files under a project path
//  by hashing file paths, modification dates, and sizes — without reading content.
//

import CryptoKit
import Foundation

/* folderprivate */
enum SourceFingerprint {
	/**
	 Returns a hex-encoded SHA-256 hash of all `.swift` files under `projectPath`,
	 using each file's path, modification date, and size as input.
	 Sorting by path ensures a deterministic result regardless of filesystem enumeration order.
	 Returns nil if the path cannot be enumerated.
	 */
	static func compute(for projectPath: String) -> String? {
		let url = URL(fileURLWithPath: projectPath)
		guard let enumerator = FileManager.default.enumerator(
			at: url,
			includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
			options: [.skipsHiddenFiles]
		) else { return nil }

		var entries: [(path: String, mtime: Double, size: Int)] = []

		for case let fileURL as URL in enumerator {
			guard fileURL.pathExtension == "swift" else { continue }
			guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
			      let mtime = values.contentModificationDate?.timeIntervalSinceReferenceDate,
			      let size = values.fileSize
			else { continue }
			entries.append((path: fileURL.path, mtime: mtime, size: size))
		}

		entries.sort { $0.path < $1.path }

		var hasher = SHA256()
		for entry in entries {
			let token = "\(entry.path)|\(entry.mtime)|\(entry.size)\n"
			hasher.update(data: Data(token.utf8))
		}
		let digest = hasher.finalize()
		return digest.map { String(format: "%02x", $0) }.joined()
	}
}
