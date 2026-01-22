//
//  NSColorExtensions.swift
//  Treeswift
//
//  Extensions for NSColor with lighter/darker utilities
//

import AppKit
import Foundation
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
