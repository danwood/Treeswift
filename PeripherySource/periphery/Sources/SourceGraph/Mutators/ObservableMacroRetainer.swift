import Configuration
import Foundation
import Shared

/// Retains types used as property types in @Observable-annotated types.
///
/// The @Observable macro synthesizes backing storage and accessor code in macro expansion files
/// (@__swiftmacro_*.swift). Periphery does not walk these expansion files when building its
/// reference graph, so types that are only referenced via the synthesized code appear unused.
/// This retainer compensates by explicitly retaining types declared as property types inside
/// @Observable types.
final class ObservableMacroRetainer: SourceGraphMutator {
    private let graph: SourceGraph

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        // Detect @Observable types by presence of implicit backing storage properties.
        // Periphery's indexer skips macro expansion (.unit) dependencies, so @Observable
        // attribute metadata is never populated on the class declaration. Instead, detect
        // @Observable indirectly: the macro synthesizes an implicit varInstance named
        // "_propName" for every stored property "propName". A class/struct that has at least
        // one such pair is almost certainly @Observable.
        let observableTypes = graph.declarations(ofKinds: [.class, .struct])
            .filter { decl in
                let implicitBackingNames = decl.declarations
                    .filter { $0.kind == .varInstance && $0.isImplicit && $0.name.hasPrefix("_") }
                    .map(\.name)
                guard !implicitBackingNames.isEmpty else { return false }
                let nonImplicitNames = Set(decl.declarations
                    .filter { $0.kind == .varInstance && !$0.isImplicit }
                    .map(\.name))
                return implicitBackingNames.contains { nonImplicitNames.contains(String($0.dropFirst())) }
            }

        guard !observableTypes.isEmpty else { return }

        // Type declaration kinds that can legitimately appear as property types.
        let typeKinds: Set<Declaration.Kind> = [.enum, .struct, .class, .typealias, .associatedtype]

        for observableType in observableTypes {
            // Suppress redundantInternalAccessibility on implicit backing storage properties
            // (_propName synthesized by @Observable). Their indexstore positions point into
            // macro expansion files, so Periphery assigns wrong line numbers and flags them
            // with spurious redundantInternalAccessibility warnings.
            let implicitProps = observableType.declarations.filter { $0.kind == .varInstance && $0.isImplicit }
            for implicitProp in implicitProps {
                graph.unmarkRedundantInternalAccessibility(implicitProp)
            }

            let props = observableType.declarations.filter { $0.kind == .varInstance && !$0.isImplicit }
            for property in props {
                // For every stored property of an @Observable type, suppress redundant-internal-
                // accessibility warnings. The @Observable macro synthesizes accessor boilerplate
                // that references these properties from macro-expansion code which Periphery
                // cannot see. As a result, Periphery may incorrectly mark them as only used within
                // the same file and suggest downgrading to `private` — even when they are accessed
                // from other files in the module. Unmarking prevents that incorrect downgrade.
                graph.unmarkRedundantInternalAccessibility(property)

                for ref in property.references {
                    guard typeKinds.contains(ref.declarationKind),
                          let targetDecl = graph.declaration(withUsr: ref.usr) else { continue }
                    graph.markRetained(targetDecl)
                    graph.unmarkRedundantPublicAccessibility(targetDecl)
                    graph.unmarkRedundantInternalAccessibility(targetDecl)
                    // Also retain and unmark all children — members of a retained type are
                    // implicitly required (the type is used externally, so its API must compile).
                    for child in targetDecl.declarations {
                        graph.markRetained(child)
                        graph.unmarkRedundantPublicAccessibility(child)
                        graph.unmarkRedundantInternalAccessibility(child)
                    }
                }
            }
        }
    }
}
