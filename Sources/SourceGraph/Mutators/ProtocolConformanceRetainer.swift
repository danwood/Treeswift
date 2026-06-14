import Configuration
import Foundation
import Shared

/// Retains protocol declarations that have at least one conforming type in the source graph.
///
/// Without this retainer, a protocol that is never used as an existential type but is conformed
/// to by one or more types would be flagged as unused. The conformance declaration (`: TheProtocol`)
/// is a `.related` reference from the conforming type to the protocol, which does not count as a
/// "normal" reference that would mark the protocol as used through the reference chain.
///
/// Retaining such protocols prevents false-positive `.unused` results that would cause destructive
/// removals: deleting the protocol body while leaving the conformance declarations in place, which
/// then fail to compile.
final class ProtocolConformanceRetainer: SourceGraphMutator {
    private let graph: SourceGraph

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        for protocolDecl in graph.declarations(ofKind: .protocol) {
            guard !graph.isRetained(protocolDecl) else { continue }

            let hasConformer = graph.references(to: protocolDecl).contains { reference in
                reference.kind == .related && reference.parent?.kind.isConformableKind == true
            }

            if hasConformer {
                graph.markRetained(protocolDecl)
            }
        }
    }
}
