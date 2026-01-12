//
//  IconCache.swift
//  Treeswift
//
//  Caches file and folder icons for performance
//

import AppKit
import UniformTypeIdentifiers

@MainActor
class IconCache {
	static let shared = IconCache()

	private var cache: [String: NSImage] = [:]
	private let cachedFolderIcon: NSImage

	private init() {
		cachedFolderIcon = NSWorkspace.shared.icon(for: .folder)
	}

	func folderIcon() -> NSImage {
		return cachedFolderIcon
	}

	func fileIcon(forPath path: String) -> NSImage {
		// Use file extension as cache key instead of full path
		let ext = (path as NSString).pathExtension
		let cacheKey = ext.isEmpty ? "unknown" : ext

		if let cached = cache[cacheKey] {
			return cached
		}

		// Fetch icon and cache it
		let icon = NSWorkspace.shared.icon(forFile: path)
		cache[cacheKey] = icon
		return icon
	}
}
