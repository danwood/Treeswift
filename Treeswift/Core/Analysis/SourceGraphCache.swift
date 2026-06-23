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
				attributeNames: Array(decl.attributes).map(\.description).sorted(),
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

	 Steps 1a (build Declaration objects) and 4a (build Reference objects) run
	 concurrently on background threads, then sequential wiring and set-building
	 follow. The `progress` callback is invoked after each phase with a 0…1 fraction
	 and a human-readable label so the UI can report sub-project progress.
	 */
	nonisolated static func restore(
		declarationSnapshots: [DeclarationSnapshot],
		referenceSnapshots: [ReferenceSnapshot],
		scanResultSnapshots: [ScanResultSnapshot],
		progress: (@MainActor (Double, String) -> Void)? = nil
	) async -> (sourceGraph: RestoredSourceGraph, scanResults: [ScanResult])? {
		// Build SourceFile cache to avoid creating duplicate objects for the same path.
		// Declarations and references share many file paths — deduplicating cuts allocations significantly.
		let allPaths = Set(declarationSnapshots.map(\.filePath) + referenceSnapshots.map(\.filePath))
		let sourceFileByPath: [String: SourceFile] = Dictionary(
			uniqueKeysWithValues: allPaths.map { path in (path, SourceFile(path: FilePath(path), modules: [])) }
		)

		// Split decl and ref arrays into chunks — one chunk per available core — and
		// process all chunks concurrently. This spreads the object-construction work
		// across all 10 logical cores instead of running on a single thread.
		let coreCount = ProcessInfo.processInfo.activeProcessorCount
		@Sendable func chunked<T>(_ array: [T], into n: Int) -> [[T]] {
			guard n > 1, array.count > n else { return [array] }
			let size = (array.count + n - 1) / n
			return stride(from: 0, to: array.count, by: size).map {
				Array(array[$0 ..< min($0 + size, array.count)])
			}
		}

		// Steps 1a + 4a: build raw objects across all cores concurrently
		async let declPairs: [(usrs: [String], decl: Declaration)] = withTaskGroup(
			of: [(usrs: [String], decl: Declaration)].self
		) { group in
			for chunk in chunked(declarationSnapshots, into: coreCount) {
				group.addTask(priority: .userInitiated) {
					var pairs: [(usrs: [String], decl: Declaration)] = []
					pairs.reserveCapacity(chunk.count)
					for snap in chunk {
						guard let kind = Declaration.Kind(rawValue: snap.kind) else { continue }
						let sourceFile = sourceFileByPath[snap.filePath] ?? SourceFile(
							path: FilePath(snap.filePath),
							modules: []
						)
						let loc = Location(
							file: sourceFile,
							line: snap.line,
							column: snap.column,
							endLine: snap.endLine,
							endColumn: snap.endColumn
						)
						let decl = Declaration(name: snap.name ?? "", kind: kind, usrs: Set(snap.usrs), location: loc)
						decl.isImplicit = snap.isImplicit
						decl.modifiers = Set(snap.modifiers)
						decl
							.attributes = Set(snap.attributeNames
								.map { DeclarationAttribute(name: $0, arguments: nil) })
						if let acc = Accessibility(rawValue: snap.accessibility) {
							decl.accessibility = DeclarationAccessibility(
								value: acc,
								isExplicit: snap.accessibilityIsExplicit
							)
						}
						pairs.append((snap.usrs, decl))
					}
					return pairs
				}
			}
			var all: [(usrs: [String], decl: Declaration)] = []
			all.reserveCapacity(declarationSnapshots.count)
			for await chunk in group {
				all.append(contentsOf: chunk)
			}
			return all
		}

		async let rawRefs: [(ref: Reference, parentUSR: String?)] = withTaskGroup(
			of: [(ref: Reference, parentUSR: String?)].self
		) { group in
			for chunk in chunked(referenceSnapshots, into: coreCount) {
				group.addTask(priority: .userInitiated) {
					var refs: [(ref: Reference, parentUSR: String?)] = []
					refs.reserveCapacity(chunk.count)
					for snap in chunk {
						guard let refKind = Reference.Kind(rawValue: snap.kind),
						      let declKind = Declaration.Kind(rawValue: snap.declarationKind) else { continue }
						let sourceFile = sourceFileByPath[snap.filePath] ?? SourceFile(
							path: FilePath(snap.filePath),
							modules: []
						)
						let loc = Location(file: sourceFile, line: snap.line, column: snap.column)
						let ref = Reference(
							name: snap.name ?? "",
							kind: refKind,
							declarationKind: declKind,
							usr: snap.usr,
							location: loc
						)
						if let role = Reference.Role(rawValue: snap.role) {
							ref.role = role
						}
						refs.append((ref, snap.parentUSR))
					}
					return refs
				}
			}
			var all: [(ref: Reference, parentUSR: String?)] = []
			all.reserveCapacity(referenceSnapshots.count)
			for await chunk in group {
				all.append(contentsOf: chunk)
			}
			return all
		}

		// Await both concurrent multi-core builds
		let (resolvedDeclPairs, resolvedRawRefs) = await (declPairs, rawRefs)
		if let progress { await MainActor.run { progress(0.35, "Building declaration map…") } }

		// Step 1b: populate usrToDecl lookup
		var usrToDecl: [String: Declaration] = Dictionary(minimumCapacity: resolvedDeclPairs.count * 2)
		for (usrs, decl) in resolvedDeclPairs {
			for usr in usrs {
				usrToDecl[usr] = decl
			}
		}
		if let progress { await MainActor.run { progress(0.5, "Wiring parents…") } }

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
		usedDeclarations.reserveCapacity(declarationSnapshots.count / 2)
		for snap in declarationSnapshots where snap.isUsed {
			guard let primaryUSR = snap.usrs.first,
			      let decl = usrToDecl[primaryUSR] else { continue }
			usedDeclarations.insert(decl)
		}
		let allDeclarations = Set(usrToDecl.values)
		if let progress { await MainActor.run { progress(0.7, "Wiring references…") } }

		// Step 4b: Wire reference parent links (needs usrToDecl from Step 1b)
		var allReferencesByUsr: [String: Set<Reference>] = Dictionary(minimumCapacity: resolvedRawRefs.count)
		for (ref, parentUSR) in resolvedRawRefs {
			if let parentUSR, let parent = usrToDecl[parentUSR] {
				ref.parent = parent
				parent.references.insert(ref)
			}
			allReferencesByUsr[ref.usr, default: []].insert(ref)
		}
		if let progress { await MainActor.run { progress(0.85, "Reconstructing scan results…") } }

		// Step 5: Reconstruct ScanResults
		var scanResults: [ScanResult] = []
		scanResults.reserveCapacity(scanResultSnapshots.count)
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

	private nonisolated static func restoreAnnotation(
		_ snap: ScanResultSnapshot,
		usrToDecl _: [String: Declaration],
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
final nonisolated class RestoredSourceGraph: SourceGraphProtocol {
	let allDeclarations: Set<Declaration>
	let unusedDeclarations: Set<Declaration>
	private let allReferencesByUsr: [String: Set<Reference>]

	fileprivate init(
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
