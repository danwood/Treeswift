import Foundation

/**
Unified error type for all code modification operations.

Provides consistent error handling across deletion, modification,
and comment insertion operations.
*/
enum CodeModificationError: Error, LocalizedError {
	case cannotReadFile(String)
	case cannotWriteFile(String)
	case invalidLineRange(Int, Int)
	case patternNotFound(String)
	case missingEndLocation
	case missingSourceGraph

	var errorDescription: String? {
		switch self {
		case .cannotReadFile(let path):
			"Cannot read source file: \(path)"
		case .cannotWriteFile(let path):
			"Cannot write to source file: \(path)"
		case .invalidLineRange(let line, let max):
			"Invalid line \(line) (file has \(max) lines)"
		case .patternNotFound(let pattern):
			"Pattern '\(pattern)' not found in source"
		case .missingEndLocation:
			"Declaration missing end location"
		case .missingSourceGraph:
			"Source graph required for this operation"
		}
	}
}
