//
//  StringExtensions.swift
//  Treeswift
//
//  String extensions for console logging
//

import Foundation

extension String {
	/// Truncates string to specified length, appending ellipsis if truncated
	nonisolated func truncated(to maxLength: Int) -> String {
		if self.count > maxLength {
			return String(self.prefix(maxLength)) + "…"
		}
		return self
	}

	/// Logs this string to stderr (or other FileHandle) with a newline appended
	nonisolated func logToConsole(handle: FileHandle = .standardError) {
		guard let data = "\(self)\n".data(using: .utf8) else { return }
		try? handle.write(contentsOf: data)
	}
}
