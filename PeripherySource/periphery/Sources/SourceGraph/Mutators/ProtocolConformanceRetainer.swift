import Configuration
import Foundation
import Shared

/// Retains protocol declarations that have at least one conforming type in the source graph, and
/// retains the witness members of a conforming type that is itself reachable.
///
/// Without protocol retention, a protocol that is never used as an existential type but is conformed
/// to by one or more types would be flagged as unused. The conformance declaration (`: TheProtocol`)
/// is a `.related` reference from the conforming type to the protocol, which does not count as a
/// "normal" reference that would mark the protocol as used through the reference chain.
///
/// Without witness retention, a member that satisfies a protocol requirement (e.g. `func play()`
/// witnessing `TransportPlaying.play()`) is flagged unused when nothing calls it via the protocol
/// type — even though the type still declares the conformance. Removing it produces
/// "type 'X' does not conform to protocol 'P'". We retain such witnesses, but only for a conforming
/// type that is itself reachable (retained, or referenced by something other than the conformance
/// itself). A wholly-dead conforming type keeps no witnesses, so it still collapses entirely with no
/// dangling conformance.
final class ProtocolConformanceRetainer: SourceGraphMutator {
    private let graph: SourceGraph

    required init(graph: SourceGraph, configuration _: Configuration, swiftVersion _: SwiftVersion) {
        self.graph = graph
    }

    func mutate() {
        for protocolDecl in graph.declarations(ofKind: .protocol) {
            // Only concrete nominal conformers (class/struct/enum/actor) declared in source. Extensions
            // on external types (e.g. `extension DispatchQueue: P`) are excluded — their members are not
            // ours to retain and Swift may favour the type's own implementation anyway.
            let conformers = graph.references(to: protocolDecl)
                .filter { ref in
                    ref.kind == .related
                        && (ref.parent.map { Declaration.Kind.concreteTypeKinds.contains($0.kind) } ?? false)
                }
                .compactMap(\.parent)

            guard !conformers.isEmpty else { continue }

            if !graph.isRetained(protocolDecl) {
                graph.markRetained(protocolDecl)
            }

            retainWitnesses(of: protocolDecl, conformers: Set(conformers))
        }
    }

    // MARK: - Private

    /// A conforming type is reachable when it is retained or has a reference that is not merely the
    /// conformance itself (a `.related` edge). This avoids retaining witnesses of a wholly-dead type.
    private func isReachable(_ declaration: Declaration) -> Bool {
        if graph.isRetained(declaration) { return true }
        return graph.references(to: declaration).contains { $0.kind != .related }
    }

    /// Retains the witness members of each reachable conformer that satisfy a requirement of THIS
    /// protocol. Inversion (`ProtocolConformanceReferenceBuilder`) left each witness with an incoming
    /// `.related` reference whose USR is a requirement of the protocol. We retain a witness only when:
    ///   - its conformer is reachable (so a wholly-dead conformer still collapses entirely), and
    ///   - the witness satisfies a requirement OF THIS protocol (the incoming `.related` USR is one of
    ///     `protocolDecl`'s requirement USRs), and
    ///   - it is a func/var/subscript witness — NOT a typealias witnessing an `associatedtype` (which
    ///     has its own reachability and must stay removable when unused).
    private func retainWitnesses(of protocolDecl: Declaration, conformers: Set<Declaration>) {
        let requirements = Set(protocolDecl.declarations)
        guard !requirements.isEmpty else { return }

        for conformer in conformers where isReachable(conformer) {
            for member in conformer.declarations {
                guard member.kind != .typealias, member.kind != .associatedtype else { continue }
                // The witness↔requirement edge created by inversion is an incoming `.related` reference
                // whose parent is the protocol requirement this member satisfies. Match against THIS
                // protocol's requirements so we never retain a witness of some other protocol.
                let witnessesThisProtocol = graph.references(to: member).contains {
                    $0.kind == .related && ($0.parent.map { requirements.contains($0) } ?? false)
                }
                guard witnessesThisProtocol else { continue }
                graph.markRetained(member)
                for accessor in member.declarations where accessor.kind.isAccessorKind {
                    graph.markRetained(accessor)
                }
            }
        }
    }
}
