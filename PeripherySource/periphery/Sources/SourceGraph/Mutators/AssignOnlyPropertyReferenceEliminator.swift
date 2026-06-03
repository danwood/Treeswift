import Configuration
import Foundation
import Shared

enum AssignOnlyPropertyAnalyzer {
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
              !property.isLetBinding,
              // A protocol property can technically be assigned and never used when the protocol is
              // used as an existential type, however communicating that succinctly would be very
              // tricky, and most likely just lead to confusion. Here we filter out protocol
              // properties and thus restrict this analysis only to concrete properties.
              property.parent?.kind != .protocol,
              !graph.references(to: property).contains(where: { $0.parent?.parent?.kind == .protocol }),
              let setter = property.declarations.first(where: { $0.kind == .functionAccessorSetter }),
              let getter = property.declarations.first(where: { $0.kind == .functionAccessorGetter }),
              graph.references(to: setter).contains(where: { $0.kind != .retained }),
              !graph.references(to: getter).contains(where: { $0.kind != .retained }),
              // If all non-retained writes to this property come from initializers, the property is a
              // genuine stored value that is simply never read externally. Removing the declaration
              // would leave orphaned `self.x = x` assignments in the init body, breaking the build.
              !graph.references(to: setter).filter({ $0.kind != .retained }).allSatisfy({ $0.parent?.kind == .functionConstructor })
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
            if AssignOnlyPropertyAnalyzer.isAssignOnlyProperty(property, graph: graph, configuration: configuration) {
                if graph.isRetained(property) {
                    graph.markSuppressedAssignOnlyProperty(property)
                } else {
                    graph.markAssignOnlyProperty(property)
                }
            } else if isLetPropertyWithInitBodyAssignment(property) {
                // A `let` stored property that is assigned inside an init body cannot be safely
                // removed: removing the declaration leaves `self.x = x` orphaned in the init,
                // causing a build error. Retain the property so it does not appear as `unused`.
                graph.markRetained(property)
            }
        }
    }

    // MARK: - Private

    /**
     Returns true when a `let` stored property is assigned exclusively inside an init body.
     Such properties must be retained: removing the declaration while leaving the init body
     intact would leave an orphaned `self.x = x` assignment that breaks the build.
     */
    private func isLetPropertyWithInitBodyAssignment(_ property: Declaration) -> Bool {
        guard property.isLetBinding,
              property.kind.isVariableKind,
              let setter = property.declarations.first(where: { $0.kind == .functionAccessorSetter }),
              graph.references(to: setter).contains(where: {
                  $0.kind != .retained && $0.parent?.kind == .functionConstructor
              })
        else { return false }

        return true
    }
}
