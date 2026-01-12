//
//  EmojiRender.swift
//  ResponsiveDesignExamples
//
//  Created by Dan Wood on 7/1/24.
//

import SwiftUI
import CoreGraphics

// Uncomment this if not defined elsewhere in the code!
// A cross-platform convenience initializer
// #if os(iOS) || os(watchOS) || os(tvOS)
// extension Image {
// 	init(nsImage: UIImage) {
// 		self.init(uiImage: nsImage)
// 	}
// }
// #endif

// Give NSImage a more convenient way to extract CGImage, to mirror UIImage API
#if os(macOS)
extension NSImage {
	var cgImage: CGImage? {
		cgImage(forProposedRect: nil, context: nil, hints: nil)
	}
}
#endif

extension String {

	static let nativeEmojiSize: CGFloat = 160

	// Different classes and methods for rendering emoji, and slightly differing fudging offsets!!!
#if os(iOS) || os(watchOS) || os(tvOS)
	func render(size: CGFloat) -> UIImage {		// Based on answers found here: https://stackoverflow.com/q/38809425
		let font = UIFont.systemFont(ofSize: size)
		let cgSize = CGSize(width: size, height: size)
		// FIXME: Should use ImageRenderer instead of UIGraphicsImageRenderer
		return UIGraphicsImageRenderer(size: cgSize).image { context in
			self.draw(at: CGPoint(x: -5.5 * (size/Self.nativeEmojiSize), y: -16 * (size/Self.nativeEmojiSize)),
					  withAttributes: [.font: font])
		}
	}
#elseif os(macOS)
	func render(size: CGFloat) -> NSImage {
		let cgSize = CGSize(width: size, height: size)
		return NSImage(size: cgSize, flipped: false) { _ in
			let attributes = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: size)]
			let attributedString = NSAttributedString(string: self, attributes: attributes)
			attributedString.draw(at: CGPoint(x: -5.5 * (size/Self.nativeEmojiSize), y: -14 * (size/Self.nativeEmojiSize)))
			return true
		}
	}
#endif
}

// Create an image from emoji string. It's private because we should use the cache to avoid re-rendering same emoji.
extension Image {
	init(emoji: String) {
		let nsImage = emoji.render(size: String.nativeEmojiSize)	// 160 is "native" emoji bitmap size
		// extracting CGImage may result in nil — fallback is to use the NSImage/UIImage init so we can return non-optional Image
		if let cgImage = nsImage.cgImage {
			self.init(cgImage, scale: 1, label: Text(emoji))	// attach emoji string for accessibility
		} else {
			self.init(nsImage: nsImage)	// fallback, no accessibilty attached
		}
	}
}

struct EmojiTestView: View {

	var body: some View {
		Image(emoji: "🔵")
			.resizable()
			.aspectRatio(1, contentMode: .fit)
			.background(.yellow)
		// For testing, be sure to use an emoji that goes all the way to the edge like the circles.
		// This is easiest to verify that it's centered properly and not clipped
	}
}

#Preview {
	EmojiTestView()
}
