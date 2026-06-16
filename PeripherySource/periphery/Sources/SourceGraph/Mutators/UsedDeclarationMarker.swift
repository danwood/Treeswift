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
        // Evaluate ancestor dereference status from a stable pre-mutation snapshot to avoid
        // order-dependent behavior when iterating sets and removing references.
        let dereferencedDeclarations = graph.allDeclarations.filter {
            !(graph.isRetained($0) || graph.hasReferences(to: $0))
        }

        let dereferencedAncestors = Set(dereferencedDeclarations)
        var referencesToRemove = Set<Reference>()

        for protocolDecl in graph.declarations(ofKind: .protocol) {
            for memberDecl in protocolDecl.declarations {
                for relatedRef in memberDecl.related {
                    guard let relatedDecl = graph.declaration(withUsr: relatedRef.usr) else { continue }

                    let hasDereferencedAncestor = relatedDecl.ancestralDeclarations.contains {
                        dereferencedAncestors.contains($0)
                    }

                    if hasDereferencedAncestor {
                        referencesToRemove.insert(relatedRef)
                    }
                }
            }
        }

        for reference in referencesToRemove {
            graph.remove(reference)
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
            // to ensure the property declaration itself is not falsely flagged as unused. This also
            // covers property-wrapper projected values (e.g. `$foo` for `@State var foo`), which are
            // recorded against the accessor rather than the property.
            if declaration.kind.isAccessorKind, let parent = declaration.parent {
                markUsed([parent])
            }

            // When any method or function member is used, the containing type is also used.
            // The Swift index store sometimes records only a reference to the member (e.g. the
            // static method USR) without a separate reference to the enclosing type at the call
            // site. Propagating upward ensures the containing type — and by extension the
            // child-function returnType/parameterType walk below — fires reliably, preventing
            // nested types that appear only in sibling method signatures from being falsely flagged.
            if declaration.kind.isFunctionKind, let parent = declaration.parent {
                markUsed([parent])
            }

            for ref in declaration.references {
                markUsed(declarationsReferenced(by: ref))
            }

            for ref in declaration.related {
                markUsed(declarationsReferenced(by: ref))
            }

            // Follow type references from child property declarations. Property type references are
            // associated with the property declaration by the indexer, not the containing type.
            // Walking varType references ensures types used as property types are marked used when
            // the parent type is used.
            for childDecl in declaration.declarations where childDecl.kind.isVariableKind {
                for ref in childDecl.references where ref.role == .varType {
                    markUsed(declarationsReferenced(by: ref))
                }
            }

            // Follow return-type and parameter-type references from child function/method
            // declarations. A nested type used only as a return or parameter type of a sibling
            // method has no external references of its own. Walking these references when the parent
            // type is marked used ensures such nested types are retained and not falsely flagged.
            for childDecl in declaration.declarations where childDecl.kind.isFunctionKind {
                for ref in childDecl.references where ref.role == .returnType || ref.role == .parameterType {
                    markUsed(declarationsReferenced(by: ref))
                }
            }

            // When a type is marked used, check whether any of its stored-property children name a
            // type in lexical scope as their declared type. The Swift index store does not always
            // emit a reference occurrence when a type is used only as the type annotation of a stored
            // property. This applies both to nested types declared within the same parent scope
            // (e.g. `private let status: PhraseStatus` where `PhraseStatus` is a nested enum) and to
            // sibling or enclosing-scope types referenced the same way (e.g. a top-level
            // `let placement: ToolPlacement` where the `ToolPlacement` enum is a file-scope sibling
            // of the property's owning struct). Without this the type has no incoming references and
            // is falsely flagged as unused, producing a removal that leaves the surviving property's
            // type annotation dangling. Resolution follows Swift's lexical lookup: the owning type's
            // nested types first, then each enclosing scope outward to the module root.
            markUsedTypesNamedByStoredProperties(of: declaration)
        }
    }

    // Marks used any type named by the declared type of a stored property of `declaration`, resolved
    // against the names visible in `declaration`'s lexical scope. Covers the cases where the index
    // store omits the property's type reference, ensuring a kept stored property never leaves its
    // type annotation referring to a declaration that is itself flagged unused.
    private func markUsedTypesNamedByStoredProperties(of declaration: Declaration) {
        let storedProperties = declaration.declarations.filter { $0.kind.isVariableKind && $0.declaredType != nil }
        guard !storedProperties.isEmpty else { return }

        let typesByNameInScope = typesByNameInLexicalScope(of: declaration)
        guard !typesByNameInScope.isEmpty else { return }

        for property in storedProperties {
            guard let declaredType = property.declaredType else { continue }

            let baseName = PropertyTypeSanitizer.sanitize(declaredType)
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            if let resolved = typesByNameInScope[baseName] {
                // Mark the resolved type used so the kept property's type annotation never dangles.
                // For an enum, also mark its cases: an enum reached only by this name-based fallback
                // has no reference occurrences for its cases, and the cases cannot be independently
                // dead while the enum is used as a value type. Do NOT mark members of class/struct
                // types — those have their own reachability, and over-retaining them would keep
                // genuinely-dead methods and properties alive.
                if resolved.kind == .enum {
                    let cases = resolved.declarations.filter { $0.kind == .enumelement }
                    markUsed(Set(cases).union([resolved]))
                } else {
                    markUsed([resolved])
                }
            }
        }
    }

    // Builds a name-to-declaration map of the type declarations visible by simple name from within
    // `declaration`: its own nested types, then the types declared in each enclosing scope outward to
    // the module root. Inner scopes take precedence over outer ones so that a nested type shadows an
    // enclosing type of the same name, matching Swift resolution. Restricting the search to the
    // lexical scope chain (rather than every declaration in the graph) avoids retaining unrelated,
    // genuinely-dead types that merely share a name in another scope.
    private func typesByNameInLexicalScope(of declaration: Declaration) -> [String: Declaration] {
        var typesByName: [String: Declaration] = [:]

        func record(_ candidates: Set<Declaration>) {
            for candidate in candidates where Declaration.Kind.concreteTypeKinds.contains(candidate.kind) {
                // Inner scopes are recorded first; do not let an outer scope overwrite a closer match.
                if typesByName[candidate.name] == nil {
                    typesByName[candidate.name] = candidate
                }
            }
        }

        record(declaration.declarations)

        var scope: Declaration? = declaration
        while let current = scope {
            if let parent = current.parent {
                record(parent.declarations)
                scope = parent
            } else {
                record(graph.rootDeclarations)
                scope = nil
            }
        }

        return typesByName
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
