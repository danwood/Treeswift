import Foundation
import SourceGraph

public struct ScanResult {
    public enum Annotation {
        case unused
        case assignOnlyProperty
        case redundantProtocol(references: Set<Reference>, inherited: Set<String>)
        case redundantPublicAccessibility(modules: Set<String>)
        case redundantInternalAccessibility(suggestedAccessibility: Accessibility?)
        case redundantFilePrivateAccessibility(containingTypeName: String?)
        case redundantAccessibility(files: Set<SourceFile>)
        case superfluousIgnoreCommand
    }

    public let declaration: Declaration
    public let annotation: Annotation

    // Explicit public init so external modules can construct ScanResult.
    public init(declaration: Declaration, annotation: Annotation) {
        self.declaration = declaration
        self.annotation = annotation
    }

    public var usrs: Set<String> {
        if case .superfluousIgnoreCommand = annotation {
            return declaration.usrs.mapSet { "superfluous-ignore-\($0)" }
        }
        return declaration.usrs
    }
}
