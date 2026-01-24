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
}
