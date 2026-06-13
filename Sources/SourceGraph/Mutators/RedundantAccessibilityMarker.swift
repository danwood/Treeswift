import Configuration
import Shared

/// Identifies declarations with explicit access modifiers that match their parent type's default member access.
///
/// Swift access control rules:
/// - Members of private/fileprivate/internal types default to the same access level as the type
/// - Members of public/open types default to INTERNAL (not public/open)
///
/// This mutator checks:
/// - Only explicit modifiers (not implicit/inferred)
/// - Redundant setter-specific modifiers like `private(set)` when they match the main access level
/// - Nested types and their members
/// - Extensions inherit the extended type's access level
final class RedundantAccessibilityMarker: SourceGraphMutator {
    private let graph: SourceGraph
    private let configuration: Configuration

    required init(graph: SourceGraph, configuration: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
        self.configuration = configuration
    }

    func mutate() throws {
        guard !configuration.disableRedundantAccessAnalysis else { return }

        let nonExtensionKinds = graph.rootDeclarations.filter { !$0.kind.isExtensionKind }
        let extensionKinds = graph.rootDeclarations.filter(\.kind.isExtensionKind)

        // Check descendants of root declarations for redundant access modifiers.
        // This feature detects redundant member-level access within containing types.
        //
        // We use swift-syntax to capture source-written modifiers, which allows us to:
        // - Detect setter-specific modifiers like private(set), internal(set), etc.
        // - Preserve source-level access distinctions (the modifiers array contains what was written)
        //
        // Root-level declarations are not checked because this feature is specifically about
        // detecting when a member's access modifier is redundant with its enclosing type's
        // default member access. Root-level access is handled by other analyzers.
        for decl in nonExtensionKinds {
            markRedundantAccessDescendants(from: decl)
        }

        for decl in extensionKinds {
            try validateExtension(decl)
        }
    }

    private func validateExtension(_ decl: Declaration) throws {
        // Extensions inherit the extended type's access level.
        if decl.accessibility.isExplicit,
           let extendedDecl = try? graph.extendedDeclaration(forExtension: decl),
           decl.accessibility.value == extendedDecl.accessibility.value,
           decl.accessibility.value != .public,
           decl.accessibility.value != .open
        {
            mark(decl)
        }

        // Check extension members
        markRedundantAccessDescendants(from: decl)
    }

    private func mark(_ decl: Declaration) {
        guard !graph.isRetained(decl) else { return }

        graph.markRedundantAccessibility(decl, file: decl.location.file)
    }

    private func markRedundantAccessDescendants(from decl: Declaration) {
        for child in decl.declarations where !child.isImplicit {
            // Check if setter modifier exists and if it's redundant
            let setterModifier = child.modifiers.first { $0.contains("(set)") }
            let hasRedundantSetterModifier: Bool
            if let setterModifier {
                // Extract access level from "private(set)" → "private"
                let setterAccessLevel = setterModifier.replacingOccurrences(of: "(set)", with: "")
                // Check if setter access matches main access
                hasRedundantSetterModifier = (setterAccessLevel == child.accessibility.value.rawValue)
            } else {
                hasRedundantSetterModifier = false
            }

            // Determine if we should flag this declaration
            let shouldFlag: Bool = if child.accessibility.value != .public,
                                      child.accessibility.value != .open
            {
                // Flag if setter modifier is redundant (regardless of parent scope)
                // OR if explicit access matches parent scope (regardless of setter)
                hasRedundantSetterModifier ||
                    (child.accessibility.isExplicit &&
                        child.accessibility.value == decl.accessibility.value)
            } else {
                false
            }

            if shouldFlag, !graph.isRetained(child) {
                mark(child)
            }

            markRedundantAccessDescendants(from: child)
        }
    }
}
