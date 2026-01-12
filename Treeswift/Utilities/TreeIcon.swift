//
//  TreeIcon.swift
//  Treeswift
//
//  Unified icon type for tree views supporting SF Symbols, emojis, and image resources
//
//  NOTE: Swift 6 Concurrency Warning
//  Despite explicit nonisolated Hashable conformance and separation of @MainActor methods
//  into their own extension, Swift 6 still emits one global warning:
//  "main actor-isolated conformance of 'TreeIcon' to 'Hashable' cannot be used in nonisolated context"
//  This appears to be a Swift compiler limitation when combining @MainActor extensions with
//  nonisolated protocol conformances. The warning is benign - TreeIcon works correctly in all
//  nonisolated Sendable contexts. The @unchecked Sendable conformance is safe because all
//  associated values are Sendable (String, CGFloat).
//

import SwiftUI

enum TreeIcon: @unchecked Sendable {
	case systemImage(String)
	case emoji(String)
	case emojiOnSystemImage(String, String, CGFloat)
	case imageResource(String)

	nonisolated var asText: String {
		switch self {
		case .systemImage(let name):
			return "[\(name)]"
		case .emoji(let emoji):
			return emoji
		case .emojiOnSystemImage(let emoji, _, _):
			return emoji
		case .imageResource(let name):
			return "[\(name)]"
		}
	}
}

// Main-actor-isolated view building methods in separate extension
// to prevent isolation from affecting Hashable conformance
@MainActor
extension TreeIcon {
	@ViewBuilder
	func view(size: CGFloat = 16) -> some View {
		switch self {
		case .systemImage(let name):
			Image(systemName: name)
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(width: size, height: size)
		case .emoji(let emoji):
			Image(emoji: emoji)
				.resizable()
				.aspectRatio(1, contentMode: .fit)
				.help(emojiTooltip(for: emoji))
				.frame(width: size, height: size)
		case .emojiOnSystemImage(let emoji, let name, let scale):
			ZStack {
				Image(systemName: name)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: size, height: size)
				Image(emoji: emoji)
					.resizable()
					.aspectRatio(1, contentMode: .fit)
					.frame(width: size * scale, height: size * scale)
			}
			.help(emojiTooltip(for: emoji))

		case .imageResource(let name):
			Image(name)
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(width: size, height: size)
		}
	}

	private func emojiTooltip(for icon: String) -> String {
		switch icon {
		case "🔷": "Main App entry point (@main)"
		case "🖼️": "SwiftUI View"
		case "🟤": "AppKit class (inherits from NS* type)"
		case "🟦": "Struct"
		case "🔵": "Class"
		case "🚦": "Enum"
		case "📜": "Protocol"
		case "⚡️": "Function"
		case "🫥": "Property or Variable"
		case "🏷️": "Type alias"
		case "🔮": "Macro"
		case "⚖️": "Precedence group"
		case "🧩": "Extension"
		case "⬜️": "Other declaration type"
		case "⚠️": "No symbols found"
		default: "Symbol"
		}
	}
}

// Explicit nonisolated Hashable conformance to prevent main-actor isolation
// from @MainActor methods affecting equality checks in Sendable contexts
extension TreeIcon: Hashable {
	nonisolated func hash(into hasher: inout Hasher) {
		switch self {
		case .systemImage(let name):
			hasher.combine(0)
			hasher.combine(name)
		case .emoji(let emoji):
			hasher.combine(1)
			hasher.combine(emoji)
		case .emojiOnSystemImage(let emoji, let name, let scale):
			hasher.combine(2)
			hasher.combine(emoji)
			hasher.combine(name)
			hasher.combine(scale)
		case .imageResource(let name):
			hasher.combine(3)
			hasher.combine(name)
		}
	}

	nonisolated static func == (lhs: TreeIcon, rhs: TreeIcon) -> Bool {
		switch (lhs, rhs) {
		case (.systemImage(let l), .systemImage(let r)):
			return l == r
		case (.emoji(let l), .emoji(let r)):
			return l == r
		case (.emojiOnSystemImage(let le, let ln, let ls), .emojiOnSystemImage(let re, let rn, let rs)):
			return le == re && ln == rn && ls == rs
		case (.imageResource(let l), .imageResource(let r)):
			return l == r
		default:
			return false
		}
	}
}

#Preview("emoji") {
	
	var size: CGFloat { 100 }
	
	VStack {
		TreeIcon.emoji("🔵").view(size: size)
			.background(Color.orange.opacity(0.3))
			.padding()
		
		TreeIcon.systemImage("document").view(size: size)
			.background(Color.orange.opacity(0.3))
			.padding()
		
		TreeIcon.emojiOnSystemImage("🖼️", "folder", 0.6).view(size: size)
			.background(Color.orange.opacity(0.3))
			.padding()
	}
	.background(Color.black.opacity(0.1))
	.padding(100)
}
