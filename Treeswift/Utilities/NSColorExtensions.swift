//
//  NSColorExtensions.swift
//  Treeswift
//
//  Extensions for NSColor with lighter/darker utilities
//

import Foundation
import AppKit
import SwiftUI

extension NSColor {
	/* Creates a lighter version of the color using HSB color space.

	   The function reduces saturation and increases brightness to produce
	   a more natural-looking lighter color. For already-bright colors, saturation
	   reduction is more significant than brightness increase.

	   - Parameter percentage: The amount to lighten the color, in the range 0.0 to 1.0.
	     - `0.0` returns the original color unchanged
	     - `0.2` produces a subtle lightening
	     - `0.4` (default) produces a moderate lightening
	     - `0.6` produces a strong lightening
	     - `1.0` produces maximum lightening (approaches white)
	   - Returns: A new `NSColor` instance with adjusted brightness and saturation. */
	func lighter(by percentage: CGFloat = 0.4) -> NSColor {
		guard let rgbColor = usingColorSpace(.deviceRGB) else { return self }

		var hue: CGFloat = 0
		var saturation: CGFloat = 0
		var brightness: CGFloat = 0
		var alpha: CGFloat = 0

		rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

		let newBrightness = min(brightness + (1.0 - brightness) * percentage, 1.0)
		let newSaturation = max(saturation * (1.0 - percentage), 0.0)

		return NSColor(hue: hue, saturation: newSaturation, brightness: newBrightness, alpha: alpha)
	}

	/* Creates a darker version of the color using HSB color space.

	   The function decreases brightness while slightly increasing saturation to maintain
	   color richness and produce a more natural-looking darker color.

	   - Parameter percentage: The amount to darken the color, in the range 0.0 to 1.0.
	     - `0.0` returns the original color unchanged
	     - `0.2` produces a subtle darkening
	     - `0.4` (default) produces a moderate darkening
	     - `0.6` produces a strong darkening
	     - `1.0` produces maximum darkening (approaches black)
	   - Returns: A new `NSColor` instance with adjusted brightness and saturation. */
	func darker(by percentage: CGFloat = 0.4) -> NSColor {
		guard let rgbColor = usingColorSpace(.deviceRGB) else { return self }

		var hue: CGFloat = 0
		var saturation: CGFloat = 0
		var brightness: CGFloat = 0
		var alpha: CGFloat = 0

		rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

		let newBrightness = max(brightness * (1.0 - percentage), 0.0)
		let newSaturation = min(saturation + (1.0 - saturation) * percentage * 0.3, 1.0)

		return NSColor(hue: hue, saturation: newSaturation, brightness: newBrightness, alpha: alpha)
	}
}

private struct ColorRow: View {
	let name: String
	let color: NSColor

	var body: some View {
		HStack(spacing: 12) {
			Text(name)
				.frame(width: 120, alignment: .leading)
				.font(.system(.body, design: .monospaced))

			ColorSwatch(color: color.darker(by: 0.8), label: "-80%")
			ColorSwatch(color: color.darker(by: 0.6), label: "-60%")
			ColorSwatch(color: color.darker(by: 0.4), label: "-40%")
			ColorSwatch(color: color.darker(by: 0.2), label: "-20%")
			ColorSwatch(color: color, label: "Base")
			ColorSwatch(color: color.lighter(by: 0.2), label: "+20%")
			ColorSwatch(color: color.lighter(by: 0.4), label: "+40%")
			ColorSwatch(color: color.lighter(by: 0.6), label: "+60%")
			ColorSwatch(color: color.lighter(by: 0.8), label: "+80%")
		}
		.padding(.vertical, 4)
	}
}

private struct ColorSwatch: View {
	let color: NSColor
	let label: String

	var body: some View {
		VStack(spacing: 2) {
			RoundedRectangle(cornerRadius: 4)
				.fill(Color(color))
				.frame(width: 60, height: 20)
				.overlay(
					RoundedRectangle(cornerRadius: 4)
						.strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
				)
			Text(label)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
	}
}

#Preview {
	ScrollView {
		VStack(alignment: .leading, spacing: 8) {
			Text("NSColor Lighter/Darker Preview")
				.font(.title2)
				.padding(.bottom, 8)


			VStack(alignment: .leading, spacing: 2) {
				ColorRow(name: "systemRed", color: .systemRed)
				ColorRow(name: "systemOrange", color: .systemOrange)
				ColorRow(name: "systemYellow", color: .systemYellow)
				ColorRow(name: "systemGreen", color: .systemGreen)
				ColorRow(name: "systemMint", color: .systemMint)
				ColorRow(name: "systemTeal", color: .systemTeal)
				ColorRow(name: "systemCyan", color: .systemCyan)
				ColorRow(name: "systemBlue", color: .systemBlue)
				ColorRow(name: "systemIndigo", color: .systemIndigo)
				ColorRow(name: "systemPurple", color: .systemPurple)
				ColorRow(name: "systemPink", color: .systemPink)
				ColorRow(name: "systemBrown", color: .systemBrown)
				ColorRow(name: "systemGray", color: .systemGray)
				ColorRow(name: "systemFill", color: .systemFill)
			}
		}
	}
	.padding(20)
	.frame(height: 800)
}
