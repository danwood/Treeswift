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

        // 🌲 Issue 15: Retain a class initializer that is the sole non-implicit constructor
        // of its parent class and assigns at least one stored property. Classes (unlike structs)
        // do not receive a compiler-synthesized memberwise initializer. Removing the only explicit
        // init of a class that has non-default stored properties leaves those properties
        // un-initializable, breaking compilation.
        for constructor in graph.declarations(ofKind: .functionConstructor) {
            guard isRequiredClassInit(constructor) else { continue }
            graph.markRetained(constructor)
        }

        // 🌲 Issue 14: Mark as used any nested type that is referenced as the declared type of
        // a sibling stored property in the same parent type. Even when both the parent type and
        // the nested type are unused, removing only the nested type leaves the sibling property's
        // type annotation unresolvable, breaking compilation. We mark the nested type AND all of
        // its descendants (enum cases, members) used — marking only the type is insufficient
        // because an unused enum case is reported independently, and after its removal empty-
        // container cleanup deletes the now-empty enum, re-orphaning the annotation. markUsed
        // (not markRetained) is required because nested decls are retained via a retained
        // reference, which ScanResultBuilder's final filter (checks retainedDeclarations only)
        // does not see.
        //
        // NOTE: kept deliberately NARROW (same-parent nesting only). A broader "any type used as
        // any property's declaredType" sweep over-marks types as used, which perturbs
        // ignoreUnusedDescendents and causes large over-removal regressions. The cross-type case
        // (e.g. a Codable property whose type is a separate top-level struct) is handled precisely
        // by CodablePropertyRetainer retaining the property's declared type — not here.
        for decl in graph.declarations(ofKinds: Declaration.Kind.concreteTypeKinds) {
            guard let parent = decl.parent,
                  Declaration.Kind.concreteTypeKinds.contains(parent.kind)
            else { continue }
            let typeName = decl.name
            let usedAsSiblingPropertyType = parent.declarations.contains { sibling in
                guard sibling.kind.isVariableKind, let declared = sibling.declaredType else { return false }
                let baseName = PropertyTypeSanitizer.sanitize(declared)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                return baseName == typeName
            }
            if usedAsSiblingPropertyType {
                graph.markUsed(decl)
                for descendant in decl.descendentDeclarations {
                    graph.markUsed(descendant)
                }
            }
        }
    }

    // MARK: - Private

    /**
     Returns true when a class initializer is the sole non-implicit constructor of its parent
     class AND the class has at least one stored `var` or `let` property that is assigned in
     any constructor of that class.

     Classes do not receive a compiler-synthesized memberwise initializer (unlike structs).
     If the only explicit init is removed, stored properties that require initialization (i.e.
     assigned in init bodies) become un-initializable, breaking compilation.

     Detection: parent must be a class, the constructor must be the only non-implicit init
     in the parent, and at least one stored-variable child of the parent must have its setter
     (or itself, for let bindings) referenced from a functionConstructor of the parent.
     */
    private func isRequiredClassInit(_ constructor: Declaration) -> Bool {
        guard constructor.kind == .functionConstructor,
              !constructor.isImplicit,
              let parent = constructor.parent,
              parent.kind == .class
        else { return false }

        // Must be the sole non-implicit init of the class
        let explicitInits = parent.declarations.filter {
            $0.kind == .functionConstructor && !$0.isImplicit
        }
        guard explicitInits.count == 1 else { return false }

        // At least one stored property must be assigned in some constructor of this class.
        // For `var` properties: check if the setter is referenced from any constructor.
        // For `let` properties: check direct refs to property/getter from any constructor.
        // Using `?.kind == .functionConstructor` (not identity) because init body assignments
        // in the graph may reference through accessor children rather than directly.
        for property in parent.declarations where property.kind.isVariableKind {
            if let setter = property.declarations.first(where: { $0.kind == .functionAccessorSetter }),
               graph.references(to: setter).contains(where: {
                   $0.kind != .retained && $0.parent?.kind == .functionConstructor
               })
            {
                return true
            }
            // Direct reference path (covers let properties and alternate codegen)
            let accessors = property.declarations.filter {
                $0.kind == .functionAccessorGetter || $0.kind == .functionAccessorSetter
            }
            for decl in [property] + Array(accessors) {
                if graph.references(to: decl).contains(where: {
                    $0.kind != .retained && $0.parent?.kind == .functionConstructor
                }) {
                    return true
                }
            }
        }

        return false
    }

    /**
     Returns true when a `let` stored property is assigned exclusively inside an init body.
     Such properties must be retained: removing the declaration while leaving the init body
     intact would leave an orphaned `self.x = x` assignment that breaks the build.

     For `var` properties the Swift indexer emits the init-body assignment as a reference
     to the implicit `functionAccessorSetter` child. For `let` properties Swift does not
     generate a setter child — the init-body write is recorded as a direct reference to
     the property itself (or its getter) from the `functionConstructor`. Both paths are
     checked here so that neither kind is incorrectly removed.
     */
    private func isLetPropertyWithInitBodyAssignment(_ property: Declaration) -> Bool {
        guard property.isLetBinding,
              property.kind.isVariableKind
        else { return false }

        // Path 1: setter child present (covers var-like let in unusual codegen paths)
        if let setter = property.declarations.first(where: { $0.kind == .functionAccessorSetter }),
           graph.references(to: setter).contains(where: {
               $0.kind != .retained && $0.parent?.kind == .functionConstructor
           })
        {
            return true
        }

        // Path 2: direct references to the property (or its getter) from a constructor.
        // This is the common case for `public let` stored properties in structs: the
        // init-body `self.x = x` assignment is recorded as a direct ref to the property.
        let allRelevantDecls: [Declaration] = [property] + property.declarations.filter {
            $0.kind == .functionAccessorGetter || $0.kind == .functionAccessorSetter
        }
        for decl in allRelevantDecls {
            if graph.references(to: decl).contains(where: {
                $0.kind != .retained && $0.parent?.kind == .functionConstructor
            }) {
                return true
            }
        }

        // Path 3: for let stored properties, Swift's indexer may record NO references at all
        // for the init-body assignment self.x = x (especially for public let in public structs).
        // Fall back to name matching: if the parent type has an explicit init whose parameter
        // list contains a parameter with the same name as this property, treat the property
        // as having an init-body assignment and retain it.
        if let parent = property.parent,
           Declaration.Kind.concreteTypeKinds.contains(parent.kind)
        {
            let propName = property.name
            for initDecl in parent.declarations where initDecl.kind == .functionConstructor && !initDecl.isImplicit {
                // initDecl.name looks like "init(a:b:c:)" — check if propName appears as a label
                let initName = initDecl.name
                let paramLabels = initName
                    .dropFirst("init(".count)
                    .dropLast(1)
                    .split(separator: ":")
                    .map(String.init)
                if paramLabels.contains(propName) {
                    return true
                }
            }
        }

        return false
    }
}
