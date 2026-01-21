import Foundation

/**
 Types of code modification operations that can be performed.

 Used to unify different modification patterns (deletion, access control fixes,
 ignore comment handling) under a single type system.
 */
enum ModificationOperation {
	case deleteDeclaration
	case deleteImport
	case insertIgnoreComment
	case removeIgnoreComment
	case fixAccessControl(AccessControlFix)
}

/**
 Types of access control modifications.

 Covers all redundant access control warnings from Periphery, including
 both removal of redundant keywords and insertion of suggested keywords.
 */
enum AccessControlFix {
	/// Remove public keyword (becomes internal, the default)
	case removePublic

	/// Remove internal keyword (stays internal, effectively no change)
	case removeInternal

	/// Remove private keyword (becomes internal)
	case removePrivate

	/// Remove fileprivate keyword (becomes internal)
	case removeFilePrivate

	/// Remove accessibility keyword when Periphery doesn't specify which
	case removeAccessibility(current: String?)

	/// Insert private keyword before declaration
	case insertPrivate

	/// Insert fileprivate keyword before declaration
	case insertFilePrivate
}

/**
 Plan for a code modification operation.

 Describes what will be modified without actually performing the modification.
 Returned by analysis functions and consumed by execution functions.
 */
struct ModificationPlan {
	let operation: ModificationOperation
	let startLine: Int
	let endLine: Int
	let replacementText: String?
	let includeTrailingBlankLine: Bool
}
