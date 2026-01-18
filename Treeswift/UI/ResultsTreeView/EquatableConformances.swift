import Foundation
import PeripheryKit
import SourceGraph

// Equatable conformance for FilterState used by UI to detect when filtering inputs change.
// Adjust the compared properties to the public API of FilterState available in this project.
extension FilterState: Equatable {
	public static func == (lhs: FilterState, rhs: FilterState) -> Bool {
		// Heuristic equality: compare properties that influence filtering.
		// If FilterState already exposes an identifier or equatable properties, compare them here.
		// Fallback: compare by object identity to avoid false positives.
		// Replace the following lines with concrete property comparisons if available.
		if let l = lhs as AnyObject?, let r = rhs as AnyObject? {
			return l === r
		}
		// As a last resort, treat as not equal.
		return false
	}
}

// Equatable conformance for ScanResult so arrays of ScanResult can be observed with onChange.
// Equality should reflect a stable identity of a scan result; USRs and location are a good proxy.
extension ScanResult: @retroactive Equatable {
	public static func == (lhs: ScanResult, rhs: ScanResult) -> Bool {
		// Compare by declaration USR set and annotation, and by primary location.
		// Accessors via helpers to avoid reaching into internals.
		let lDecl = lhs.declaration
		let rDecl = rhs.declaration
		let lLoc = ScanResultHelper.location(from: lDecl)
		let rLoc = ScanResultHelper.location(from: rDecl)
		return lhs.usrs == rhs.usrs && lhs.annotation == rhs.annotation && lLoc == rLoc
	}
}
