//
//  SourceGraphCache.swift
//  Treeswift
//
//  Codable snapshot types for serializing SourceGraph and ScanResults to disk,
//  plus RestoredSourceGraph for reconstructing the graph from cache.
//

import Foundation
import PeripheryKit
import SourceGraph
import SystemPackage

// MARK: - Snapshot Types

/**
 Codable representation of a Declaration for cache serialization.
 Stores only the fields needed by Treeswift's removal operations.
 */
nonisolated struct DeclarationSnapshot: Codable, Sendable {
	let usrs: [String]
	let kind: String
	let name: String?
	let filePath: String
	let line: Int
	let column: Int
	let endLine: Int?
	let endColumn: Int?
	let isImplicit: Bool
	let isUsed: Bool
	let parentUSR: String?
	let modifiers: [String]
	let attributeNames: [String]
	let accessibility: String
	let accessibilityIsExplicit: Bool
}

/**
 Codable representation of a Reference for cache serialization.
 */
nonisolated struct ReferenceSnapshot: Codable, Sendable {
	let usr: String
	let kind: String
	let declarationKind: String
	let name: String?
	let role: String
	let filePath: String
	let line: Int
	let column: Int
	let parentUSR: String?
}

/**
 Codable representation of a ScanResult for cache serialization.
 Uses the declaration's primary USR to link back to the restored Declaration.
 */
nonisolated struct ScanResultSnapshot: Codable, Sendable {
	let declarationUSR: String
	let annotationKind: String
	// Associated values for specific annotation kinds
	let redundantPublicModules: [String]?
	let redundantInternalSuggestedAccessibility: String?
	let redundantFilePrivateContainingTypeName: String?
	let redundantProtocolInheritedUSRs: [String]?
}

// MARK: - Serializer

/**
 Serializes and deserializes SourceGraph + ScanResults to/from Codable snapshots.
 */
enum SourceGraphSerializer {
	/**
	 Serializes a SourceGraph and its associated ScanResults into flat snapshot arrays.
	 Returns nil if the graph has no declarations (e.g., empty scan).
	 */
	static func serialize(
		graph: SourceGraph,
		scanResults: [ScanResult]
	) -> (declarations: [DeclarationSnapshot], references: [ReferenceSnapshot], scanResults: [ScanResultSnapshot]) {
		let usedSet = graph.usedDeclarations

		// Serialize all declarations
		let declSnapshots: [DeclarationSnapshot] = graph.allDeclarations.map { decl in
			let loc = decl.location
			let parentUSR = decl.parent?.usrs.first
			return DeclarationSnapshot(
				usrs: Array(decl.usrs).sorted(),
				kind: decl.kind.rawValue,
				name: decl.name,
				filePath: loc.file.path.string,
				line: loc.line,
				column: loc.column,
				endLine: loc.endLine,
				endColumn: loc.endColumn,
				isImplicit: decl.isImplicit,
				isUsed: usedSet.contains(decl),
				parentUSR: parentUSR,
				modifiers: Array(decl.modifiers).sorted(),
				attributeNames: Array(decl.attributes).map(\.name).sorted(),
				accessibility: decl.accessibility.value.rawValue,
				accessibilityIsExplicit: decl.accessibility.isExplicit
			)
		}

		// Serialize all references
		let refSnapshots: [ReferenceSnapshot] = graph.allReferences.map { ref in
			let loc = ref.location
			let parentUSR = ref.parent?.usrs.first
			return ReferenceSnapshot(
				usr: ref.usr,
				kind: ref.kind.rawValue,
				declarationKind: ref.declarationKind.rawValue,
				name: ref.name,
				role: ref.role.rawValue,
				filePath: loc.file.path.string,
				line: loc.line,
				column: loc.column,
				parentUSR: parentUSR
			)
		}

		// Serialize scan results
		let scanSnapshots: [ScanResultSnapshot] = scanResults.map { result in
			let primaryUSR = result.usrs.sorted().first ?? ""
			switch result.annotation {
			case .unused, .assignOnlyProperty, .superfluousIgnoreCommand:
				return ScanResultSnapshot(
					declarationUSR: primaryUSR,
					annotationKind: annotationKindString(result.annotation),
					redundantPublicModules: nil,
					redundantInternalSuggestedAccessibility: nil,
					redundantFilePrivateContainingTypeName: nil,
					redundantProtocolInheritedUSRs: nil
				)
			case let .redundantPublicAccessibility(modules):
				return ScanResultSnapshot(
					declarationUSR: primaryUSR,
					annotationKind: "redundantPublicAccessibility",
					redundantPublicModules: Array(modules).sorted(),
					redundantInternalSuggestedAccessibility: nil,
					redundantFilePrivateContainingTypeName: nil,
					redundantProtocolInheritedUSRs: nil
				)
			case let .redundantInternalAccessibility(suggestedAccessibility):
				return ScanResultSnapshot(
					declarationUSR: primaryUSR,
					annotationKind: "redundantInternalAccessibility",
					redundantPublicModules: nil,
					redundantInternalSuggestedAccessibility: suggestedAccessibility?.rawValue,
					redundantFilePrivateContainingTypeName: nil,
					redundantProtocolInheritedUSRs: nil
				)
			case let .redundantFilePrivateAccessibility(containingTypeName):
				return ScanResultSnapshot(
					declarationUSR: primaryUSR,
					annotationKind: "redundantFilePrivateAccessibility",
					redundantPublicModules: nil,
					redundantInternalSuggestedAccessibility: nil,
					redundantFilePrivateContainingTypeName: containingTypeName,
					redundantProtocolInheritedUSRs: nil
				)
			case let .redundantProtocol(_, inherited):
				return ScanResultSnapshot(
					declarationUSR: primaryUSR,
					annotationKind: "redundantProtocol",
					redundantPublicModules: nil,
					redundantInternalSuggestedAccessibility: nil,
					redundantFilePrivateContainingTypeName: nil,
					redundantProtocolInheritedUSRs: Array(inherited).sorted()
				)
			case let .redundantAccessibility(files):
				return ScanResultSnapshot(
					declarationUSR: primaryUSR,
					annotationKind: "redundantAccessibility",
					redundantPublicModules: nil,
					redundantInternalSuggestedAccessibility: nil,
					redundantFilePrivateContainingTypeName: nil,
					redundantProtocolInheritedUSRs: files.map(\.path.string).sorted()
				)
			}
		}

		return (declSnapshots, refSnapshots, scanSnapshots)
	}

	private static func annotationKindString(_ annotation: ScanResult.Annotation) -> String {
		switch annotation {
		case .unused: "unused"
		case .assignOnlyProperty: "assignOnlyProperty"
		case .superfluousIgnoreCommand: "superfluousIgnoreCommand"
		case .redundantProtocol: "redundantProtocol"
		case .redundantPublicAccessibility: "redundantPublicAccessibility"
		case .redundantInternalAccessibility: "redundantInternalAccessibility"
		case .redundantFilePrivateAccessibility: "redundantFilePrivateAccessibility"
		case .redundantAccessibility: "redundantAccessibility"
		}
	}

	/**
	 Reconstructs a RestoredSourceGraph and ScanResults array from cached snapshots.
	 Returns nil if reconstruction fails.
	 */
	static func restore(
		declarationSnapshots: [DeclarationSnapshot],
		referenceSnapshots: [ReferenceSnapshot],
		scanResultSnapshots: [ScanResultSnapshot]
	) -> (sourceGraph: RestoredSourceGraph, scanResults: [ScanResult])? {
		// Step 1: Build Declaration objects (no parent/refs yet)
		var usrToDecl: [String: Declaration] = [:]

		for snap in declarationSnapshots {
			guard let kind = Declaration.Kind(rawValue: snap.kind) else { continue }
			let sourceFile = SourceFile(path: FilePath(snap.filePath), modules: [])
			let loc = Location(
				file: sourceFile,
				line: snap.line,
				column: snap.column,
				endLine: snap.endLine,
				endColumn: snap.endColumn
			)
			let decl = Declaration(kind: kind, usrs: Set(snap.usrs), location: loc)
			decl.name = snap.name
			decl.isImplicit = snap.isImplicit
			decl.modifiers = Set(snap.modifiers)
			decl.attributes = Set(snap.attributeNames.map { DeclarationAttribute(name: $0, arguments: nil) })
			if let acc = Accessibility(rawValue: snap.accessibility) {
				decl.accessibility = DeclarationAccessibility(value: acc, isExplicit: snap.accessibilityIsExplicit)
			}
			for usr in snap.usrs {
				usrToDecl[usr] = decl
			}
		}

		// Step 2: Wire parent links and rebuild children sets
		for snap in declarationSnapshots {
			guard let primaryUSR = snap.usrs.first,
			      let decl = usrToDecl[primaryUSR] else { continue }
			if let parentUSR = snap.parentUSR, let parent = usrToDecl[parentUSR] {
				decl.parent = parent
				parent.declarations.insert(decl)
			}
		}

		// Step 3: Build used/unused sets
		var usedDeclarations = Set<Declaration>()
		for snap in declarationSnapshots where snap.isUsed {
			guard let primaryUSR = snap.usrs.first,
			      let decl = usrToDecl[primaryUSR] else { continue }
			usedDeclarations.insert(decl)
		}
		let allDeclarations = Set(usrToDecl.values)

		// Step 4: Build Reference objects and wire parent links
		var allReferencesByUsr: [String: Set<Reference>] = [:]

		for snap in referenceSnapshots {
			guard let refKind = Reference.Kind(rawValue: snap.kind),
			      let declKind = Declaration.Kind(rawValue: snap.declarationKind) else { continue }
			let sourceFile = SourceFile(path: FilePath(snap.filePath), modules: [])
			let loc = Location(file: sourceFile, line: snap.line, column: snap.column)
			let ref = Reference(kind: refKind, declarationKind: declKind, usr: snap.usr, location: loc)
			ref.name = snap.name
			if let role = Reference.Role(rawValue: snap.role) {
				ref.role = role
			}
			if let parentUSR = snap.parentUSR, let parent = usrToDecl[parentUSR] {
				ref.parent = parent
				parent.references.insert(ref)
			}
			allReferencesByUsr[snap.usr, default: []].insert(ref)
		}

		// Step 5: Reconstruct ScanResults
		var scanResults: [ScanResult] = []
		for snap in scanResultSnapshots {
			guard let decl = usrToDecl[snap.declarationUSR] else { continue }
			let annotation = restoreAnnotation(snap, usrToDecl: usrToDecl, allReferencesByUsr: allReferencesByUsr)
			guard let annotation else { continue }
			scanResults.append(ScanResult(declaration: decl, annotation: annotation))
		}

		let graph = RestoredSourceGraph(
			allDeclarations: allDeclarations,
			usedDeclarations: usedDeclarations,
			allReferencesByUsr: allReferencesByUsr
		)

		return (graph, scanResults)
	}

	private static func restoreAnnotation(
		_ snap: ScanResultSnapshot,
		usrToDecl: [String: Declaration],
		allReferencesByUsr: [String: Set<Reference>]
	) -> ScanResult.Annotation? {
		switch snap.annotationKind {
		case "unused":
			return .unused
		case "assignOnlyProperty":
			return .assignOnlyProperty
		case "superfluousIgnoreCommand":
			return .superfluousIgnoreCommand
		case "redundantPublicAccessibility":
			return .redundantPublicAccessibility(modules: Set(snap.redundantPublicModules ?? []))
		case "redundantInternalAccessibility":
			let accessibility = snap.redundantInternalSuggestedAccessibility.flatMap { Accessibility(rawValue: $0) }
			return .redundantInternalAccessibility(suggestedAccessibility: accessibility)
		case "redundantFilePrivateAccessibility":
			return .redundantFilePrivateAccessibility(containingTypeName: snap.redundantFilePrivateContainingTypeName)
		case "redundantProtocol":
			let inheritedUSRs = Set(snap.redundantProtocolInheritedUSRs ?? [])
			let references = inheritedUSRs.flatMap { allReferencesByUsr[$0, default: []] }
			return .redundantProtocol(references: Set(references), inherited: inheritedUSRs)
		case "redundantAccessibility":
			let files = Set((snap.redundantProtocolInheritedUSRs ?? [])
				.map { SourceFile(path: FilePath($0), modules: []) })
			return .redundantAccessibility(files: files)
		default:
			return nil
		}
	}
}

// MARK: - RestoredSourceGraph

/**
 A lightweight SourceGraph substitute reconstructed from cached data.
 Conforms to SourceGraphProtocol so all removal code works identically
 whether using a live or cached graph.
 */
final class RestoredSourceGraph: SourceGraphProtocol {
	let allDeclarations: Set<Declaration>
	let unusedDeclarations: Set<Declaration>
	private let allReferencesByUsr: [String: Set<Reference>]

	init(
		allDeclarations: Set<Declaration>,
		usedDeclarations: Set<Declaration>,
		allReferencesByUsr: [String: Set<Reference>]
	) {
		self.allDeclarations = allDeclarations
		unusedDeclarations = allDeclarations.subtracting(usedDeclarations)
		self.allReferencesByUsr = allReferencesByUsr
	}

	func references(to declaration: Declaration) -> Set<Reference> {
		declaration.usrs.reduce(into: Set<Reference>()) { result, usr in
			result.formUnion(allReferencesByUsr[usr, default: []])
		}
	}

	func references(to usr: String) -> Set<Reference> {
		allReferencesByUsr[usr, default: []]
	}

	func isRetained(_ declaration: Declaration) -> Bool {
		references(to: declaration).contains { $0.kind == .retained }
	}
}
