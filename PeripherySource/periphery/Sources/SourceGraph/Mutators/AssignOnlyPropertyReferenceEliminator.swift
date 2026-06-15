import Configuration
import Foundation
import Shared

private enum AssignOnlyPropertyAnalyzer {
    static func isAssignOnlyProperty(
        _ property: Declaration,
        graph: SourceGraph,
        configuration: Configuration
    ) -> Bool {
        let defaultRetainedTypes = ["AnyCancellable", "Set<AnyCancellable>", "[AnyCancellable]", "NSKeyValueObservation"]
        let retainAssignOnlyPropertyTypes = defaultRetainedTypes + configuration.retainAssignOnlyPropertyTypes.map {
            PropertyTypeSanitizer.sanitize($0)
        }

        guard !configuration.retainAssignOnlyProperties,
              property.kind.isVariableKind,
              let declaredType = property.declaredType,
              !retainAssignOnlyPropertyTypes.contains(declaredType),
              property.attributes.isEmpty,
              !property.isComplexProperty,
              // A protocol property can technically be assigned and never used when the protocol is
              // used as an existential type, however communicating that succinctly would be very
              // tricky, and most likely just lead to confusion. Here we filter out protocol
              // properties and thus restrict this analysis only to concrete properties.
              property.parent?.kind != .protocol,
              !graph.references(to: property).contains(where: { $0.parent?.parent?.kind == .protocol }),
              let setter = property.declarations.first(where: { $0.kind == .functionAccessorSetter }),
              let getter = property.declarations.first(where: { $0.kind == .functionAccessorGetter }),
              graph.references(to: setter).contains(where: { $0.kind != .retained }),
              !graph.references(to: getter).contains(where: { $0.kind != .retained })
        else { return false }

        return true
    }
}

final class AssignOnlyPropertyReferenceEliminator: SourceGraphMutator {
    private let graph: SourceGraph
    private let configuration: Configuration

    required init(graph: SourceGraph, configuration: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
        self.configuration = configuration
    }

    func mutate() throws {
        guard !configuration.retainAssignOnlyProperties else { return }

        for property in graph.declarations(ofKinds: Declaration.Kind.variableKinds) {
            guard AssignOnlyPropertyAnalyzer.isAssignOnlyProperty(property, graph: graph, configuration: configuration) else {
                continue
            }

            if isInitializedConstant(property) {
                // The property is a `let` constant whose value is supplied by an explicit
                // initializer that is itself used. Removing the declaration would orphan the
                // `self.x = x` assignment in the initializer body and drop the matching
                // initializer parameter, breaking every call site that supplies it. The property
                // is therefore retained rather than reported, as it is not safely removable.
                graph.markRetained(property)
            } else if graph.isRetained(property) {
                graph.markSuppressedAssignOnlyProperty(property)
            } else {
                graph.markAssignOnlyProperty(property)
            }
        }
    }

    // MARK: - Private

    /// Returns true when the property is a `let` constant initialized by an explicit initializer
    /// that is referenced elsewhere.
    ///
    /// A `let` property can only be assigned once, in an initializer body. When that initializer is
    /// written explicitly and is used, its `self.x = x` assignment and corresponding parameter are
    /// load-bearing: removing the property would leave the assignment without a target and the call
    /// sites passing the argument without a parameter. Such a property is a genuine stored value
    /// that simply isn't read, not an assign-only property, so it must not be reported.
    ///
    /// A `let` initialized only by a compiler-synthesized memberwise initializer is excluded, as is
    /// one whose initializer is never called; in both cases the declaration can be removed safely.
    private func isInitializedConstant(_ property: Declaration) -> Bool {
        guard property.isLetBinding,
              let setter = property.declarations.first(where: { $0.kind == .functionAccessorSetter })
        else { return false }

        let initializers = graph.references(to: setter)
            .filter { $0.kind != .retained }
            .compactMap(\.parent)
            .filter { $0.kind == .functionConstructor && !$0.isImplicit }

        return initializers.contains { initializer in
            graph.references(to: initializer).contains { $0.kind != .retained }
        }
    }
}
