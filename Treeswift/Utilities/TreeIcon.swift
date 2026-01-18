//
//  TreeIcon.swift
//  Treeswift
//
//  Unified icon type for tree views supporting SF Symbols, emojis, and image resources
//

import SwiftUI

enum TreeIcon: @unchecked Sendable {
	case systemImage(String)
	case emoji(String)
	case emojiOnSystemImage(String, String, CGFloat)
	case imageResource(String)

	nonisolated var asText: String {
		switch self {
		case let .systemImage(name):
			"[\(name)]"
		case let .emoji(emoji):
			emoji
		case let .emojiOnSystemImage(emoji, _, _):
			emoji
		case let .imageResource(name):
			"[\(name)]"
		}
	}
}

// View building methods
extension TreeIcon {
	@ViewBuilder
	func view(size: CGFloat = 16) -> some View {
		switch self {
		case let .systemImage(name):
			Image(systemName: name)
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(width: size, height: size)
		case let .emoji(emoji):
			Image(emoji: emoji)
				.resizable()
				.aspectRatio(1, contentMode: .fit)
				.help(emojiTooltip(for: emoji))
				.frame(width: size, height: size)
		case let .emojiOnSystemImage(emoji, name, scale):
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
		case let .imageResource(name):
			Image(name)
				.resizable()
				.aspectRatio(contentMode: .fit)
				.frame(width: size, height: size)
		}
	}

	private nonisolated func emojiTooltip(for icon: String) -> String {
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
		case let .systemImage(name):
			hasher.combine(0)
			hasher.combine(name)
		case let .emoji(emoji):
			hasher.combine(1)
			hasher.combine(emoji)
		case let .emojiOnSystemImage(emoji, name, scale):
			hasher.combine(2)
			hasher.combine(emoji)
			hasher.combine(name)
			hasher.combine(scale)
		case let .imageResource(name):
			hasher.combine(3)
			hasher.combine(name)
		}
	}

	nonisolated static func == (lhs: TreeIcon, rhs: TreeIcon) -> Bool {
		switch (lhs, rhs) {
		case let (.systemImage(l), .systemImage(r)):
			l == r
		case let (.emoji(l), .emoji(r)):
			l == r
		case let (.emojiOnSystemImage(le, ln, ls), .emojiOnSystemImage(re, rn, rs)):
			le == re && ln == rn && ls == rs
		case let (.imageResource(l), .imageResource(r)):
			l == r
		default:
			false
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
