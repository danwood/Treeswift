import Foundation
import PeripheryKit

/**
 Represents different types of code modification operations.

 Provides type-safe operation dispatch for code removal and modification tasks.
 */
enum ModificationOperation {
	case deleteDeclaration
	case deleteImport
	case insertIgnoreComment
	case removeIgnoreComment
	case fixAccessControl(AccessControlFix)

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
}

/**
 Describes a planned modification to source code.

 Contains all information needed to execute the modification:
 line range, replacement text, and formatting preferences.
 */
struct ModificationPlan {
	let operation: ModificationOperation
	let startLine: Int
	let endLine: Int
	let replacementText: String?
	let includeTrailingBlankLine: Bool
}
