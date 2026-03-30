import Foundation

/**
 Represents different types of code modification operations.

 Provides type-safe operation dispatch for code removal and modification tasks.
 */

/**
 Specifies the type of access control modification to perform.

 Removal cases remove the specified keyword, making the declaration internal (Swift's default).
 Insertion cases add the keyword before the declaration keyword (not before attributes).
 */
enum AccessControlFix {
	case removePublic
	case removeInternal
	case removePrivate
	case removeFilePrivate
	case removeAccessibility(current: String?)
	case insertPrivate
	case insertFilePrivate

	/// Human-readable description for console logging.
	var logDescription: String {
		switch self {
		case .removePublic: "removed `public`"
		case .removeInternal: "removed `internal`"
		case .removePrivate: "removed `private`"
		case .removeFilePrivate: "removed `fileprivate`"
		case let .removeAccessibility(current):
			if let current { "removed `\(current)`" }
			else { "removed access modifier" }
		case .insertPrivate: "inserted `private`"
		case .insertFilePrivate: "inserted `fileprivate`"
		}
	}
}
