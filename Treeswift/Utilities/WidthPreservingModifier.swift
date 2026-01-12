//
//  WidthPreservingModifier.swift
//  Treeswift
//
//  Utilities for preserving view width across state changes
//

import SwiftUI

/*
 Width-Preserving View Modifier

 Maintains consistent view width across content state changes by using the hidden overlay pattern.
 All possible content states are hidden to establish the maximum required width, then the active
 state is overlaid on top.

 This prevents layout shifts when content changes (e.g., button labels, status text) and is
 particularly useful for toolbar items, buttons, and any view where stable width is desired.

 Usage:
   Button(action: toggle) {
	   Text(isActive ? "Active" : "Inactive")
   }
   .widthPreserving {
	   Text("Active")
	   Text("Inactive")
   }

   // Or with the newer Button initializer that includes a title and system image:
   Button("Run Scan", systemImage: isScanning ? "stop.fill" : "play.fill", action: scanAction)
       .labelStyle(.titleAndIcon)
       .widthPreserving {
           Button("Run Scan", systemImage: "play.fill", action: {})
               .labelStyle(.titleAndIcon)
           Button("Stop", systemImage: "stop.fill", action: {})
               .labelStyle(.titleAndIcon)
       }

 Performance Notes:
 - Zero runtime overhead (uses SwiftUI's built-in layout system)
 - No state management or preference keys required
 - Hidden views still participate in layout but are not rendered
 - All possible states must be known at compile time

 Best Practices:
 - Use for views with 2-5 known states
 - Ideal for toolbar buttons, toggle buttons, status indicators
 - All states in the closure should be at the same view hierarchy level
 - Works naturally with Dynamic Type and accessibility
 */

extension View {
	/// Preserves the width of this view across different content states.
	///
	/// The view will size itself to accommodate the widest content provided in `possibleStates`,
	/// preventing layout shifts when the content changes.
	///
	/// - Parameter possibleStates: A ViewBuilder containing all possible content states that
	///   this view might display. These views are hidden and used only for width calculation.
	///
	/// - Returns: A view that maintains a stable width across all possible content states.
	///
	/// - Note: The hidden views use zero spacing to ensure accurate width measurement.
	func widthPreserving<Content: View>(
		@ViewBuilder possibleStates: () -> Content
	) -> some View {
		ZStack(alignment: .top) {
			VStack(spacing: 0) {
				possibleStates()
			}
			.hidden()
			.frame(height: 0)

			self
		}
	}
}

