import Configuration
import Foundation
import Shared

final class DefaultConstructorReferenceBuilder: SourceGraphMutator {
    private let graph: SourceGraph

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        referenceDefaultConstructors()
        referenceSoleClassInitializers()
        referenceDestructors()
    }

    // MARK: - Private

    private func referenceDefaultConstructors() {
        let defaultConstructors = graph.declarations(ofKind: .functionConstructor).filter {
            // Some initializers are referenced internally, e.g by JSONEncoder/Decoder so we need
            // to assume they are referenced.
            $0.name == "init()" || $0.isImplicit
        }

        for constructor in defaultConstructors {
            reference(constructor)
        }
    }

    /// Retains a class's sole designated initializer when the class has stored state to initialize.
    ///
    /// A struct synthesizes a memberwise initializer, so an explicit struct init that's never called
    /// is genuinely dead code. A class has no such synthesis: when a class declares a stored property
    /// without a default value, the explicit initializer is the only way to construct an instance, and
    /// removing it would make the class unconstructable. This narrow case retains that initializer.
    ///
    /// The retention is deliberately limited to avoid masking dead code (see issue #1058):
    /// it fires only when the class has exactly one non-implicit initializer and at least one stored
    /// instance property. If the class has multiple explicit initializers there are alternatives, so
    /// none are retained here. If the class itself is unused it folds away entirely along with its
    /// initializer, so this retention cannot keep a dead class alive.
    private func referenceSoleClassInitializers() {
        for classDecl in graph.declarations(ofKind: .class) {
            let explicitInits = classDecl.declarations.filter {
                $0.kind == .functionConstructor && !$0.isImplicit
            }

            guard explicitInits.count == 1, let soleInit = explicitInits.first else { continue }

            let hasStoredProperty = classDecl.declarations.contains { decl in
                decl.kind == .varInstance && !isComputedProperty(decl)
            }

            guard hasStoredProperty else { continue }

            reference(soleInit)
        }
    }

    /// A computed property is identified by a getter accessor with no corresponding setter accessor.
    /// A stored property either declares no accessors or declares a synthesized get/set pair.
    private func isComputedProperty(_ property: Declaration) -> Bool {
        let hasGetter = property.declarations.contains { $0.kind == .functionAccessorGetter }
        let hasSetter = property.declarations.contains { $0.kind == .functionAccessorSetter }
        return hasGetter && !hasSetter
    }

    private func reference(_ constructor: Declaration) {
        guard let parent = constructor.parent else { return }

        for usr in constructor.usrs {
            let reference = Reference(
                name: constructor.name,
                kind: .normal,
                declarationKind: .functionConstructor,
                usr: usr,
                location: parent.location
            )
            reference.parent = parent
            graph.add(reference, from: parent)
        }
    }

    private func referenceDestructors() {
        for destructor in graph.declarations(ofKind: .functionDestructor) {
            if let parent = destructor.parent {
                for usr in destructor.usrs {
                    let reference = Reference(
                        name: destructor.name,
                        kind: .normal,
                        declarationKind: .functionDestructor,
                        usr: usr,
                        location: parent.location
                    )
                    reference.parent = parent
                    graph.add(reference, from: parent)
                }
            }
        }
    }
}
