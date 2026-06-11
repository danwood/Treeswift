import Configuration
import Foundation
import Shared

final class CodablePropertyRetainer: SourceGraphMutator {
    private let graph: SourceGraph
    private let configuration: Configuration

    required init(graph: SourceGraph, configuration: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
        self.configuration = configuration
    }

    func mutate() {
        // 🌲 Index concrete types by simple name so a retained property's declared type can be
        // resolved and retained too (see retainDeclaredType).
        let concreteTypesByName: [String: [Declaration]] = graph
            .declarations(ofKinds: Declaration.Kind.concreteTypeKinds)
            .reduce(into: [:]) { $0[$1.name, default: []].append($1) }

        if configuration.retainCodableProperties {
            for decl in graph.declarations(ofKinds: Declaration.Kind.discreteConformableKinds) {
                guard graph.isCodable(decl) else { continue }

                for decl in decl.declarations {
                    guard decl.kind == .varInstance else { continue }

                    graph.markRetained(decl)
                    graph.unmarkRedundantInternalAccessibility(decl)
                    retainDeclaredType(of: decl, concreteTypesByName: concreteTypesByName)
                }
            }
        } else if configuration.retainEncodableProperties {
            for decl in graph.declarations(ofKinds: Declaration.Kind.discreteConformableKinds) {
                guard graph.isEncodable(decl) else { continue }

                for decl in decl.declarations {
                    guard decl.kind == .varInstance else { continue }

                    graph.markRetained(decl)
                    graph.unmarkRedundantInternalAccessibility(decl)
                    retainDeclaredType(of: decl, concreteTypesByName: concreteTypesByName)
                }
            }
        }
    }

    // MARK: - Private

    /**
     🌲 Retains the concrete type used as a retained Codable/Encodable property's declared type.

     A `Codable`/`Encodable` property is retained because its presence is required for synthesized
     coding. If the property's declared type is itself a custom type that would otherwise be unused
     (e.g. `let price: PriceValue` where `PriceValue` is a separate `fileprivate struct` used only
     here), removing that type leaves the retained property's annotation unresolvable and breaks
     the build. Resolving the declared type's simple name to concrete declarations and retaining
     them — along with their descendants (enum cases, members) — prevents this. Restricting to the
     declared types of *retained* properties keeps genuinely-dead type+property pairs removable.
     */
    private func retainDeclaredType(
        of property: Declaration,
        concreteTypesByName: [String: [Declaration]]
    ) {
        guard let declared = property.declaredType else { return }
        let baseName = PropertyTypeSanitizer.sanitize(declared)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard let types = concreteTypesByName[baseName] else { return }
        for type in types {
            graph.markRetained(type)
            for descendant in type.descendentDeclarations {
                graph.markRetained(descendant)
            }
        }
    }
}
