import Configuration
import Foundation
import Shared

final class UsedDeclarationMarker: SourceGraphMutator {
    private let graph: SourceGraph

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        removeErroneousProtocolReferences()
        markUsed(graph.retainedDeclarations)

        graph.rootReferences.forEach { markUsed(declarationsReferenced(by: $0)) }

        ignoreUnusedDescendents(in: graph.rootDeclarations,
                                unusedDeclarations: graph.unusedDeclarations)
    }

    // MARK: - Private

    // Removes references from protocol member decls to conforming decls that have a dereferenced ancestor.
    private func removeErroneousProtocolReferences() {
        for protocolDecl in graph.declarations(ofKind: .protocol) {
            for memberDecl in protocolDecl.declarations {
                for relatedRef in memberDecl.related {
                    guard let relatedDecl = graph.declaration(withUsr: relatedRef.usr) else { continue }

                    let hasDereferencedAncestor = relatedDecl.ancestralDeclarations.contains {
                        !(graph.isRetained($0) || graph.hasReferences(to: $0))
                    }

                    if hasDereferencedAncestor {
                        graph.remove(relatedRef)
                    }
                }
            }
        }
    }

    private func markUsed(_ declarations: Set<Declaration>) {
        for declaration in declarations {
            guard !graph.isUsed(declaration) else { continue }

            graph.markUsed(declaration)

            // When an initializer is used, the containing type is also used.
            if declaration.kind == .functionConstructor, let parent = declaration.parent {
                markUsed([parent])
            }

            // When an accessor (getter/setter/etc.) is used, the containing property is also used.
            // The Swift index store records references to implicit accessor USRs rather than the
            // property USR when reading or writing a stored property, so we must propagate upward
            // to ensure the property declaration itself is not falsely flagged as unused.
            if declaration.kind.isAccessorKind, let parent = declaration.parent {
                markUsed([parent])
            }

            // When any method or function member is used, the containing type is also used.
            // The Swift index store sometimes records only a reference to the member (e.g. the
            // static method USR) without a separate reference to the enclosing type at the call
            // site. Propagating upward ensures the containing type — and by extension the Issue 7
            // child-function returnType/parameterType walk — fires reliably, preventing nested
            // types that appear only in sibling method signatures from being falsely flagged.
            if declaration.kind.isFunctionKind, let parent = declaration.parent {
                markUsed([parent])
            }

            for ref in declaration.references {
                markUsed(declarationsReferenced(by: ref))
            }

            for ref in declaration.related {
                markUsed(declarationsReferenced(by: ref))
            }

            // Follow type references from child property declarations.
            // Property type references are associated with the property declaration
            // by the indexer, not the containing type. Walking varType references
            // ensures types used as property types are marked used when the parent
            // type is used.
            for childDecl in declaration.declarations where childDecl.kind.isVariableKind {
                for ref in childDecl.references where ref.role == .varType {
                    markUsed(declarationsReferenced(by: ref))
                }
            }

            // Follow return-type and parameter-type references from child function/method
            // declarations. A nested type used only as a return or parameter type of a
            // sibling method has no external references of its own. Walking these
            // references when the parent type is marked used ensures that such nested
            // types (e.g. `enum Destination` inside `enum DeepLinkHandler`) are retained
            // and not falsely flagged as unused.
            for childDecl in declaration.declarations where childDecl.kind.isFunctionKind {
                for ref in childDecl.references where ref.role == .returnType || ref.role == .parameterType {
                    markUsed(declarationsReferenced(by: ref))
                }
            }

            // 🌲 Issue 13: When a type is marked used, check whether any of its stored-property
            // children reference a sibling nested type by name. The Swift index store does not
            // always emit a reference occurrence when a nested type is used as the type annotation
            // of a stored property within the same parent scope (e.g. `private let status: PhraseStatus`
            // where `PhraseStatus` is a nested enum inside the same struct). Without this walk, the
            // nested type has no incoming references and is falsely flagged as unused.
            let nestedTypesByName = declaration.declarations
                .filter { Declaration.Kind.concreteTypeKinds.contains($0.kind) }
                .reduce(into: [String: Declaration]()) { $0[$1.name] = $1 }

            if !nestedTypesByName.isEmpty {
                for childDecl in declaration.declarations where childDecl.kind.isVariableKind {
                    guard let declaredType = childDecl.declaredType else { continue }
                    let baseName = PropertyTypeSanitizer.sanitize(declaredType)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    if let nested = nestedTypesByName[baseName] {
                        markUsed([nested])
                    }
                }
            }
        }
    }

    private func declarationsReferenced(by reference: Reference) -> Set<Declaration> {
        var declarations: Set<Declaration> = []

        if let declaration = graph.declaration(withUsr: reference.usr) {
            declarations.insert(declaration)
        }

        return declarations
    }

    private func ignoreUnusedDescendents(in decls: Set<Declaration>, unusedDeclarations: Set<Declaration>) {
        for decl in decls {
            guard !decl.declarations.isEmpty || !decl.unusedParameters.isEmpty
            else { continue }

            if unusedDeclarations.contains(decl) {
                decl.descendentDeclarations.forEach { graph.markIgnored($0) }
            } else {
                ignoreUnusedDescendents(in: decl.declarations,
                                        unusedDeclarations: unusedDeclarations)
            }
        }
    }
}
