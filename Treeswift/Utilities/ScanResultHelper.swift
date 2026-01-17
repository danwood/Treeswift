//
//  ScanResultHelper.swift
//  Treeswift
//
//  Helper to extract information from ScanResult using reflection
//  Copied logic from OutputFormatter.swift
//

import Foundation
import SwiftUI
import PeripheryKit
import SourceGraph
import SystemPackage

struct ScanResultHelper {

	// Access internal properties via Mirror reflection

	nonisolated static func location(from declaration: Declaration) -> Location {
		// Check for comment command overrides first
		for command in declaration.commentCommands {
			if case let .override(overrides) = command {
				for override in overrides {
					if case let .location(file, line, column) = override {
						let sourceFile = SourceFile(path: FilePath(String(file)), modules: [])
						return Location(file: sourceFile, line: line, column: column)
					}
				}
			}
		}
		return declaration.location
	}

	nonisolated static func kindDisplayName(from declaration: Declaration) -> String {
		// Check for comment command overrides first
		for command in declaration.commentCommands {
			if case let .override(overrides) = command {
				for override in overrides {
					if case let .kind(overrideKind) = override {
						return overrideKind
					}
				}
			}
		}
		return declaration.kind.displayName
	}
	/**
	 Format warning in Xcode format: path:line:column: warning: description
	 */
	nonisolated static func formatPlainTextWarning(
		declaration: Declaration,
		annotation: ScanResult.Annotation,
		location: Location
	) -> String {
		let path = location.file.path.string
		let line = location.line
		let column = location.column
		let description = formatPlainTextDescription(declaration: declaration, annotation: annotation)
		return "\(path):\(line):\(column): warning: \(description)"
	}

	/**
	 Format plain text description without AttributedString formatting
	 */
	nonisolated private static func formatPlainTextDescription(
		declaration: Declaration,
		annotation: ScanResult.Annotation
	) -> String {
		let kindDisplayName = kindDisplayName(from: declaration)

		if let name = declaration.name {
			let prefix = "\(kindDisplayName.first?.uppercased() ?? "")\(kindDisplayName.dropFirst())"

			let suffix: String
			switch annotation {
			case .unused:
				suffix = "is unused"
			case .assignOnlyProperty:
				suffix = "is assigned, but never used"
			case .redundantProtocol:
				suffix = "is redundant as it's never used as an existential type"
			case .redundantPublicAccessibility:
				suffix = "is declared public, but not used outside of this module"
			case .superfluousIgnoreCommand:
				suffix = "is a superfluous periphery ignore command"
			}

			return "\(prefix) '\(name)' \(suffix)"
		} else {
			return "unused"
		}
	}

	// FIXME: Can these two functions be consolidated?
	
	// Format description as AttributedString with bold symbol names
	nonisolated static func formatAttributedDescription(declaration: Declaration, annotation: ScanResult.Annotation) -> AttributedString {
		let kindDisplayName = kindDisplayName(from: declaration)

		var result = AttributedString()

		if let name = declaration.name {
			// Kind prefix (e.g., "Function ")
			let prefix = AttributedString("\(kindDisplayName.first?.uppercased() ?? "")\(kindDisplayName.dropFirst()) ")
			result.append(prefix)

			// Symbol name in quotes - make it bold
			var boldName = AttributedString("'\(name)'")
			boldName.font = .body.bold()
			result.append(boldName)

			// Annotation suffix
			let suffix: String
			switch annotation {
			case .unused:
				suffix = " is unused"
			case .assignOnlyProperty:
				suffix = " is assigned, but never used"
			case .redundantProtocol:
				suffix = " is redundant as it's never used as an existential type"
			case .redundantPublicAccessibility:
				suffix = " is declared public, but not used outside of this module"
			case .superfluousIgnoreCommand:
				suffix = "is a superfluous periphery ignore command"
			}
			result.append(AttributedString(suffix))
		} else {
			result = AttributedString("unused")
		}

		return result
	}

	/**
	Highlight text in a line with specified background color.

	Searches for the text near the specified column and applies highlighting.
	Returns the line as an AttributedString with the matched text highlighted.
	Optionally makes the entire declaration portion bold when makeDeclarationBold is true.
	*/
	nonisolated static func highlightTextInLine(
		line: String,
		text: String,
		nearColumn: Int,
		backgroundColor: Color,
		makeDeclarationBold: Bool = false
	) -> AttributedString {
		var result = AttributedString()

		guard nearColumn > 0, nearColumn <= line.count else {
			return AttributedString(line)
		}

		if let range = findSymbolInLine(line: line, symbolName: text, nearColumn: nearColumn) {
			let prefix = String(line[..<range.lowerBound])
			let matchedText = String(line[range])
			let suffix = String(line[range.upperBound...])

			// For "@available… <declaration>" format, keep @available… regular, make declaration semibold
			if makeDeclarationBold {
				// Find where "… " ends (this is where declaration starts)
				if let ellipsisRange = prefix.range(of: "… ") {
					let beforeEllipsis = String(prefix[..<ellipsisRange.lowerBound])
					let afterEllipsis = String(prefix[ellipsisRange.upperBound...])

					// Regular weight prefix before "… " (this is the @available part)
					var regularPart = AttributedString(beforeEllipsis + "… ")
					regularPart.font = .system(.caption, design: .monospaced)
					result.append(regularPart)

					// Semibold part: from after "… " to end of line (this is the declaration)
					var boldPart = AttributedString(afterEllipsis)
					boldPart.font = .system(.caption, design: .monospaced).weight(.semibold)
					result.append(boldPart)

					var highlighted = AttributedString(matchedText)
					highlighted.backgroundColor = backgroundColor
					highlighted.font = .system(.caption, design: .monospaced).weight(.semibold)
					result.append(highlighted)

					var boldSuffix = AttributedString(suffix)
					boldSuffix.font = .system(.caption, design: .monospaced).weight(.semibold)
					result.append(boldSuffix)

					return result
				}
			}

			// Standard highlighting - apply semibold to entire line
			var prefixAttr = AttributedString(prefix)
			prefixAttr.font = .system(.caption, design: .monospaced).weight(.semibold)
			result.append(prefixAttr)

			var highlighted = AttributedString(matchedText)
			highlighted.backgroundColor = backgroundColor
			highlighted.font = .system(.caption, design: .monospaced).weight(.semibold)
			result.append(highlighted)

			var suffixAttr = AttributedString(suffix)
			suffixAttr.font = .system(.caption, design: .monospaced).weight(.semibold)
			result.append(suffixAttr)

			return result
		}

		return AttributedString(line)
	}

	// Extract and highlight symbol in source line at specified column
	nonisolated static func highlightSymbolInSourceLine(
		line: String,
		column: Int,
		symbolName: String?,
		makeDeclarationBold: Bool = false
	) -> AttributedString {
		// Special handling for @attribute… pattern - split into regular + semibold parts
		if makeDeclarationBold, let ellipsisRange = line.range(of: "… ") {
			var result = AttributedString()

			// Regular weight part (before and including "… ") - use secondary color
			let beforeEllipsis = String(line[..<ellipsisRange.upperBound])
			var regularPart = AttributedString(beforeEllipsis)
			regularPart.font = .system(.caption, design: .monospaced)
			regularPart.foregroundColor = Color.secondary
			result.append(regularPart)

			// Semibold part (after "… ")
			let afterEllipsis = String(line[ellipsisRange.upperBound...])

			// Now highlight the symbol in the semibold part if needed
			if let symbolName = symbolName, !symbolName.isEmpty,
			   column > beforeEllipsis.count,
			   let symbolRange = findSymbolInLine(line: afterEllipsis, symbolName: symbolName, nearColumn: column - beforeEllipsis.count) {
				let prefix = String(afterEllipsis[..<symbolRange.lowerBound])
				let matchedText = String(afterEllipsis[symbolRange])
				let suffix = String(afterEllipsis[symbolRange.upperBound...])

				let highlightColor = Color(nsColor: .selectedTextBackgroundColor).opacity(0.4)

				var prefixAttr = AttributedString(prefix)
				prefixAttr.font = .system(.caption, design: .monospaced).weight(.semibold)
				result.append(prefixAttr)

				var highlighted = AttributedString(matchedText)
				highlighted.backgroundColor = highlightColor
				highlighted.font = .system(.caption, design: .monospaced).weight(.semibold)
				result.append(highlighted)

				var suffixAttr = AttributedString(suffix)
				suffixAttr.font = .system(.caption, design: .monospaced).weight(.semibold)
				result.append(suffixAttr)
			} else {
				// No symbol to highlight, just make it semibold
				var semiboldPart = AttributedString(afterEllipsis)
				semiboldPart.font = .system(.caption, design: .monospaced).weight(.semibold)
				result.append(semiboldPart)
			}

			return result
		}

		guard column > 0, column <= line.count else {
			// Apply semibold to entire line by default
			var result = AttributedString(line)
			result.font = .system(.caption, design: .monospaced).weight(.semibold)
			return result
		}

		guard let symbolName = symbolName, !symbolName.isEmpty else {
			// Apply semibold to entire line by default
			var result = AttributedString(line)
			result.font = .system(.caption, design: .monospaced).weight(.semibold)
			return result
		}

		let highlightColor = Color(nsColor: .selectedTextBackgroundColor).opacity(0.4)

		// Try exact match first
		let exactMatch = highlightTextInLine(
			line: line,
			text: symbolName,
			nearColumn: column,
			backgroundColor: highlightColor,
			makeDeclarationBold: makeDeclarationBold
		)
		if exactMatch.characters.count > line.count {
			// Highlighting was applied (attributed string has more content due to attributes)
			return exactMatch
		}

		// Fallback: try to find longest common prefix
		// e.g., "matchesFilter(_:)" -> "matchesFilter"
		if let baseSymbol = extractBaseSymbolName(from: symbolName) {
			return highlightTextInLine(
				line: line,
				text: baseSymbol,
				nearColumn: column,
				backgroundColor: highlightColor,
				makeDeclarationBold: makeDeclarationBold
			)
		}

		// Apply semibold to entire line by default
		var result = AttributedString(line)
		result.font = .system(.caption, design: .monospaced).weight(.semibold)
		return result
	}

	/**
	Highlight the "public " keyword (including trailing whitespace) in a source line.

	Uses a semi-transparent red background to indicate text that will be deleted.
	*/
	nonisolated static func highlightRedundantPublicInLine(
		line: String
	) -> AttributedString {
		// Find "public" followed by whitespace using regex
		let pattern = #"public\s+"#
		guard let regex = try? NSRegularExpression(pattern: pattern) else {
			return AttributedString(line)
		}

		let nsRange = NSRange(line.startIndex..., in: line)
		guard let match = regex.firstMatch(in: line, range: nsRange) else {
			return AttributedString(line)
		}

		guard let range = Range(match.range, in: line) else {
			return AttributedString(line)
		}

		let prefix = String(line[..<range.lowerBound])
		let publicKeyword = String(line[range])
		let suffix = String(line[range.upperBound...])

		var result = AttributedString()
		result.append(AttributedString(prefix))

		var highlighted = AttributedString(publicKeyword)
		highlighted.backgroundColor = Color.red.opacity(0.3)
		result.append(highlighted)

		result.append(AttributedString(suffix))

		return result
	}

	// Find symbol name in line near the specified column
	nonisolated private static func findSymbolInLine(
		line: String,
		symbolName: String,
		nearColumn: Int
	) -> Range<String.Index>? {
		let searchDistance = 50

		let startOffset = max(0, nearColumn - searchDistance)
		let endOffset = min(line.count, nearColumn + searchDistance)

		let startIndex = line.index(line.startIndex, offsetBy: startOffset)
		let endIndex = line.index(line.startIndex, offsetBy: endOffset)
		let searchRange = startIndex..<endIndex

		return line.range(of: symbolName, range: searchRange)
	}

	/* Extract base symbol name by removing parameter signatures
	   e.g., "matchesFilter(_:)" -> "matchesFilter"
	         "init(from:)" -> "init"
	 */
	nonisolated private static func extractBaseSymbolName(from symbolName: String) -> String? {
		// Find the first opening parenthesis which indicates parameter list
		guard let parenIndex = symbolName.firstIndex(of: "(") else {
			return nil // No parameters found, original should have matched
		}

		let baseName = String(symbolName[..<parenIndex])

		// Only return if we got a meaningful base name
		return baseName.isEmpty ? nil : baseName
	}
}
