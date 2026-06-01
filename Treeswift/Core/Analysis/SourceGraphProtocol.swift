//
//  SourceGraphProtocol.swift
//  Treeswift
//
//  Protocol for accessing source graph data during code removal operations.
//  Implemented by both the live SourceGraph (from a scan) and RestoredSourceGraph
//  (reconstructed from cache).
//

import SourceGraph

/**
 Minimal protocol covering the SourceGraph API used by Treeswift's removal operations.

 The live SourceGraph and the cache-restored RestoredSourceGraph both conform to this
 protocol, allowing all removal code to work identically in both cases.
 */
protocol SourceGraphProtocol: AnyObject {
	nonisolated func references(to declaration: Declaration) -> Set<Reference>
	nonisolated func references(to usr: String) -> Set<Reference>
	nonisolated func isRetained(_ declaration: Declaration) -> Bool
	nonisolated var allDeclarations: Set<Declaration> { get }
	nonisolated var unusedDeclarations: Set<Declaration> { get }
}

extension SourceGraph: SourceGraphProtocol {}
