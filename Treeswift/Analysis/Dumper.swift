//
//  Dumper.swift
//  Treeswift
//
//  Created by Dan Wood on 10/10/25.
//

import Extensions
import Foundation

// @preconcurrency: SourceGraph library was written before Swift 6 concurrency
// This suppresses warnings about Sendable conformance for types from this module
// Note: Location and Declaration classes have been marked @unchecked Sendable in PeripherySource
@preconcurrency import SourceGraph
import SystemPackage
import XcodeProj

final class Dumper: Sendable {
	private nonisolated(unsafe) let highLevelKinds: Set<Declaration.Kind> = [
		.class,
		.struct,
		.enum,
		.protocol,
		.extensionClass,
		.extensionStruct,
		.extensionEnum,
		.extensionProtocol
	]

	nonisolated init() {}

	private struct Relation {
		let relationType: RelationshipType
		let location: Location
		let declaration: Declaration
	}

	// MARK: - Helper functions

	private nonisolated func isEnvironmentRelated(_ declaration: Declaration) -> Bool {
		let environmentAttributes = ["EnvironmentObject", "Environment"]
		// Check declaration attributes
		if declaration.attributes.contains(where: { environmentAttributes.contains($0.description) }) {
			return true
		}
		// Check inheritance (covers e.g. property wrappers in protocols)
		if declaration.immediateInheritedTypeReferences.contains(where: { (ref: Reference) in
			if let n = ref.name {
				return environmentAttributes.contains(where: { n.contains($0) })
			}
			return false
		}) {
			return true
		}
		// Name-based heuristics (covers e.g. property named @EnvironmentObject, etc.)
		if let name = declaration.name {
			return environmentAttributes.contains(where: { name.contains($0) })
		}
		return false
	}

	private nonisolated func conformsToView(_ decl: Declaration) -> Bool {
		DeclarationIconHelper.conformsToView(decl)
	}

	private nonisolated func isSubviewPattern(parent: Declaration, child: Declaration, ref _: Reference?) -> Bool {
		// Return true if both parent and child conform to View
		let isChildView = conformsToView(child)
		let isParentView = conformsToView(parent)
		if isParentView, isChildView {
			return true
		}
		return false
	}

	private nonisolated func isPreview(_ decl: Declaration) -> Bool {
		guard let name = decl.name else { return false }
		// Name-based heuristics
		if name.contains("Preview") || name.contains("Playground") {
			return true
		}
		// Protocol conformance (PreviewProvider)
		if decl.immediateInheritedTypeReferences.contains(where: { $0.name?.contains("PreviewProvider") == true }) {
			return true
		}
		// Widget previews (WidgetProvider)
		if decl.immediateInheritedTypeReferences.contains(where: { $0.name?.contains("WidgetProvider") == true }) {
			return true
		}
		return false
	}

	private nonisolated func isMainApp(_ decl: Declaration) -> Bool {
		DeclarationIconHelper.isMainApp(decl)
	}

	private nonisolated func getRelationshipType(
		sourceGraph: SourceGraph,
		child: Declaration,
		parent: Declaration
	) -> RelationshipType {
		let parentReferences: Set<Reference> = sourceGraph.references(to: child)

		// Added: Scan for variableInitFunctionCall references
		if parentReferences.contains(where: { $0.role == .variableInitFunctionCall }) {
			return .prop
		}

		// Check if child is nested in parent
		if child.parent == parent {
			return .embed
		}

		let sameFileReferences: Set<Reference> = parentReferences.filter { (ref: Reference) in
			// Check if this reference is in the same file as the parent
			ref.location.file.path == parent.location.file.path
		}

		if !sameFileReferences.isEmpty {
			// Check if parent uses child in a constructor call or as a struct reference
			let hasConstructorReference = sameFileReferences.contains { (ref: Reference) in
				ref.declarationKind == .functionConstructor || ref.declarationKind == .struct
			}
			if hasConstructorReference {
				// Check if this is a subview relationship (SwiftUI pattern)
				let hasSubviewReference = sameFileReferences.contains { (ref: Reference) in
					let isSubview = isSubviewPattern(parent: parent, child: child, ref: ref)
					return isSubview
				}

				if hasSubviewReference {
					return .subview
				}
				return .constructs
			}

			// Check if parent has a property of child type
			let hasPropertyReference = sameFileReferences.contains { (ref: Reference) in
				ref.declarationKind == .varInstance || ref.declarationKind == .varGlobal
			}
			if hasPropertyReference {
				return .prop
			}

			// Check if parent uses child as a parameter type
			let hasParameterReference = sameFileReferences.contains { (ref: Reference) in
				ref.declarationKind == .functionMethodInstance
			}
			if hasParameterReference {
				return .param
			}

			// Check if parent uses child as a local variable type
			let hasLocalVarReference = sameFileReferences.contains { (ref: Reference) in
				ref.declarationKind == .varLocal
			}
			if hasLocalVarReference {
				return .local
			}

			// Check if parent uses child in a static property/method
			let hasStaticReference = sameFileReferences.contains { (ref: Reference) in
				ref.declarationKind == .varStatic || ref.declarationKind == .functionMethodStatic
			}
			if hasStaticReference {
				return .staticMember
			}

			// Check if parent uses child in a method call
			let hasMethodCallReference = sameFileReferences.contains { (ref: Reference) in
				ref.declarationKind == .functionMethodInstance || ref.declarationKind == .functionMethodStatic
			}
			if hasMethodCallReference {
				return .call
			}

			// Check if parent uses child in a type annotation
			let hasTypeAnnotationReference = sameFileReferences.contains { (ref: Reference) in
				ref.declarationKind == .varInstance || ref.declarationKind == .varGlobal || ref
					.declarationKind == .varLocal
			}
			if hasTypeAnnotationReference {
				return .type
			}

			// If we have any references but couldn't categorize them specifically
			return .ref
		}

		// Check if parent inherits from child
		let hasInheritanceReference = parent.immediateInheritedTypeReferences.contains { inheritedType in
			inheritedType.name == child.name
		}
		if hasInheritanceReference {
			return .inherit
		}

		return .ref
	}

	private nonisolated func getAncestorChain(_ decl: Declaration) -> Set<Declaration> {
		var ancestors = Set<Declaration>()
		var current = decl.parent
		while let c = current {
			ancestors.insert(c)
			current = c.parent
		}
		return ancestors
	}

	// MARK: - Main Support Functions

	/// Returns the filtered declarations with high-level types in the project modules, excluding previews.
	private nonisolated func filterHighLevelDeclarations(sourceGraph: SourceGraph) -> [Declaration] {
		let projectModules = Set(sourceGraph.indexedSourceFiles.flatMap(\.modules))
		return sourceGraph.declarations(ofKinds: highLevelKinds)
			.filter { !isPreview($0) }
			.filter { !$0.kind.isExtensionKind || projectModules.contains($0.firstNameComponent) }
			.sorted(by: { $0.location < $1.location }) // TEMP sort for reproducibility
	}

	/// Finds orphaned types with no references and removes them from the declarations array.
	private nonisolated func extractOrphanedTypes(
		from declarations: inout [Declaration],
		sourceGraph: SourceGraph
	) -> [Declaration] {
		let (orphanedTypes, remaining) = declarations.partitioned { type in
			!isMainApp(type) && sourceGraph.references(to: type).isEmpty
		}
		declarations = remaining
		return orphanedTypes
	}

	/// Finds types whose only references are from getter:body and removes them from the declarations array.
	private nonisolated func extractOnlyBodyGetterReferencedTypes(
		from declarations: inout [Declaration],
		sourceGraph: SourceGraph,
		displayedTypes: Set<Declaration>
	) -> [Declaration] {
		let (onlyBodyGetterTypes, remaining) = declarations.partitioned { type in
			guard !displayedTypes.contains(type), !isMainApp(type) else { return false }
			let referencingDecls: [Declaration] = referencingDeclarations(for: type, in: sourceGraph)
			return !isMainApp(type) &&
				!referencingDecls.isEmpty &&
				referencingDecls.allSatisfy { declaration in
					declaration.kind == .functionAccessorGetter && declaration.name == "getter:body"
				}
		}
		declarations = remaining
		return onlyBodyGetterTypes
	}

	/// Extracts preview-only types and removes them from the declarations array.
	private nonisolated func extractPreviewOnlyTypes(
		from declarations: inout [Declaration],
		sourceGraph: SourceGraph,
		displayedTypes: Set<Declaration>
	) -> [Declaration] {
		let (previewOnlyTypes, remaining) = declarations.partitioned { type in
			guard !displayedTypes.contains(type), !isMainApp(type) else { return false }
			let referencingDecls: [Declaration] = referencingDeclarations(for: type, in: sourceGraph)
			guard !referencingDecls.isEmpty else { return false }
			// Check if all references come from static methods named exactly "makePreview()"
			return referencingDecls.allSatisfy { declaration in
				declaration.kind.rawValue.contains("static") && declaration.name == "makePreview()"
			}
		}
		declarations = remaining
		return previewOnlyTypes
	}

	/// Given a type and a graph, returns all declarations that reference this type.
	private nonisolated func referencingDeclarations(
		for type: Declaration,
		in sourceGraph: SourceGraph
	) -> [Declaration] {
		let references = sourceGraph.references(to: type).sorted { $0.location < $1.location }

		// Walk up from each Reference's parent to find the nearest owning Declaration
		func owningDeclaration(for ref: Reference) -> Declaration? {
			var current = ref.parent
			while let node = current {
				// Example: skip extension declarations and continue to the extended type
				if node.kind.isExtensionKind {
					current = node.parent
					continue
				}
				return node
			}
			return nil
		}
		var seen = Set<ObjectIdentifier>()
		var result: [Declaration] = []
		for ref in references {
			if let decl = owningDeclaration(for: ref) {
				let id = ObjectIdentifier(decl)
				if !seen.contains(id) {
					seen.insert(id)
					result.append(decl)
				}
			}
		}

		// Deterministic order by source location
		return result.sorted { $0.location < $1.location }
	}

	/// Builds a dictionary mapping each declaration to its referencers and their relation types.
	private nonisolated func buildTypeToReferencers(
		from declarations: [Declaration],
		sourceGraph: SourceGraph
	) -> [Declaration: [String: Relation]] {
		func findRelevantReferencingType(
			ref: Reference,
			declaration: Declaration,
			highLevelKinds: Set<Declaration.Kind>,
			sourceGraph: SourceGraph
		) -> Declaration? {
			sequence(first: ref.parent) { $0?.parent }
				.compactMap(\.self)
				.first {
					highLevelKinds.contains($0.kind) &&
						$0 != declaration &&
						!isPreview($0) &&
						!isEnvironmentRelated($0)
				}
		}

		/// Build referencers dictionary for a given declaration that is not embedded.
		func buildReferencers(for declaration: Declaration, in sourceGraph: SourceGraph) -> [String: Relation] {
			let references: [Reference] = sourceGraph.references(to: declaration).sorted { $0.location < $1.location }

			return references.reduce(into: [String: Relation]()) { referencers, ref in
				if let referencingType: Declaration = findRelevantReferencingType(
					ref: ref,
					declaration: declaration,
					highLevelKinds: highLevelKinds,
					sourceGraph: sourceGraph
				) {
					if !referencingType.kind.isExtensionKind {
						let relationshipType = getRelationshipType(
							sourceGraph: sourceGraph,
							child: declaration,
							parent: referencingType
						)
						referencers[referencingType.name ?? ""] = Relation(
							relationType: relationshipType,
							location: ref.location,
							declaration: referencingType
						)
					} else {
						// Try to find the extended type and add it to referencers instead
						if let extendedTypeName = referencingType.name {
							let extendedTypeDeclarations = sourceGraph.allDeclarations.filter { decl in
								decl.name == extendedTypeName && !decl.kind.isExtensionKind
							}
							for extDecl in extendedTypeDeclarations {
								let relationshipType = getRelationshipType(
									sourceGraph: sourceGraph,
									child: declaration,
									parent: extDecl
								)
								referencers[extDecl.name ?? ""] = Relation(
									relationType: relationshipType,
									location: ref.location,
									declaration: extDecl
								)
							}
						}
					}
				}
			}
		}

		return declarations.reduce(into: [Declaration: [String: Relation]]()) { typeToReferencers, declaration in
			if let parent = declaration.parent, let name = parent.name {
				// we want where embedded type is actually defined, NOT where it's used.
				let relation = Relation(relationType: .embed, location: declaration.location, declaration: parent)
				typeToReferencers[declaration] = [name: relation]
			} else {
				typeToReferencers[declaration] = buildReferencers(for: declaration, in: sourceGraph)
			}
		}
	}

	/// Finds types shared by multiple referencers without a common ancestor.
	private nonisolated func extractSharedTypesNoCommonAncestor(
		typeToReferencers: [Declaration: [String: Relation]],
		rootDeclaration: Declaration,
		displayedTypes: Set<Declaration>
	) -> [Declaration] {
		func hasCommonAncestors(_ referencers: [Declaration], rootDeclaration: Declaration) -> Bool {
			for i in 0 ..< referencers.count {
				for j in (i + 1) ..< referencers.count {
					let ancestorsA = getAncestorChain(referencers[i])
					let ancestorsB = getAncestorChain(referencers[j])
					let intersection = ancestorsA.intersection(ancestorsB)
					// Remove rootDeclaration from intersection if present
					let intersectionExcludingRoot = intersection.filter { $0 != rootDeclaration }
					if !intersectionExcludingRoot.isEmpty {
						return true
					}
				}
			}
			return false
		}

		return typeToReferencers.reduce(into: [Declaration]()) { acc, entry in
			let (sharedType, referencersMap) = entry
			if referencersMap.count > 1 {
				let referencers = referencersMap.values.map(\.declaration)
				if !hasCommonAncestors(referencers, rootDeclaration: rootDeclaration) {
					if !displayedTypes.contains(sharedType) {
						acc.append(sharedType)
					}
				}
			}
		}
	}

	/// Finds types that are used but not attached to our types and not yet displayed.
	private nonisolated func extractUsedButNotAttachedTypes(
		from declarations: inout [Declaration],
		displayedTypes: Set<Declaration>
	) -> [Declaration] {
		let (usedButNotAttached, remaining) = declarations
			.partitioned { !displayedTypes.contains($0) && !isMainApp($0) }
		declarations = remaining
		return usedButNotAttached
	}

	/// Checks if a function embeds a ViewModifier by looking for the .modifier() pattern
	private nonisolated func isViewModifierEmbeddingFunction(
		_ funcDecl: Declaration,
		sourceGraph _: SourceGraph
	) -> Bool {
		// Look for references to "modifier" method calls within this function
		let hasModifierCall = funcDecl.references.contains { (ref: Reference) in
			ref.name == "modifier" && ref.declarationKind == .functionMethodInstance
		}

		// Also check for "modifier(_:)" which is the full method signature
		let hasModifierCallWithParam = funcDecl.references.contains { (ref: Reference) in
			ref.name == "modifier(_:)" && ref.declarationKind == .functionMethodInstance
		}

		// For View extension functions, if they have a modifier call, they're likely ViewModifier embedders
		// since View extension functions typically return some View
		let isViewExtensionFunction = funcDecl.parent?.kind == .extensionProtocol

		// Return true if it has a modifier call and is in a View extension (which implies it returns some View)
		return (hasModifierCall || hasModifierCallWithParam) && isViewExtensionFunction
	}

	// MARK: - Structured Tree Building Functions

	/**
	 Build Categories with progressive streaming - yields each section as it completes.

	 DATA FLOW AND PARTITIONING:

	 This function progressively winnows down a list of declarations through 7 categories,
	 partitioning the master list into smaller and smaller subsets:

	 INITIAL STATE:
	 - Start with `filteredDeclarations`: all high-level types (classes, structs, enums, protocols)
	   excluding previews and non-project extensions

	 CATEGORY PROCESSING (ALL sections now extract from filteredDeclarations):

	 1. HIERARCHICAL TREE (Section 1): REMOVES from filteredDeclarations
	    - Builds main hierarchy starting from root app, marking declarations in `displayedTypes`
	    - After building section, removes all `displayedTypes` from `filteredDeclarations`
	    - List size DECREASES

	 2. VIEW EXTENSIONS (Section 2): REMOVES from filteredDeclarations
	    - Builds View extensions, continuing to populate `displayedTypes`
	    - After building section, removes all `displayedTypes` from `filteredDeclarations`
	    - List size DECREASES again

	 3. SHARED TYPES (Section 3): REMOVES from filteredDeclarations
	    - Identifies types used by multiple parents with no common ancestor
	    - After building section, removes all `sharedTypes` from `filteredDeclarations`
	    - List size DECREASES again

	 4. ORPHANED TYPES (Section 4): REMOVES from filteredDeclarations
	    - Extracts declarations with NO references at all
	    - `extractOrphanedTypes()` partitions and removes these from `filteredDeclarations`
	    - List size DECREASES again

	 5. PREVIEW-ONLY TYPES (Section 5): REMOVES from filteredDeclarations
	    - Extracts declarations ONLY referenced by makePreview() methods
	    - `extractPreviewOnlyTypes()` partitions and removes from `filteredDeclarations`
	    - List size DECREASES again

	 6. BODY-GETTER TYPES (Section 6): REMOVES from filteredDeclarations
	    - Extracts declarations ONLY referenced by getter:body, not in hierarchy
	    - `extractOnlyBodyGetterReferencedTypes()` partitions and removes from `filteredDeclarations`
	    - List size DECREASES again

	 7. USED BUT NOT ATTACHED (Section 7): Final partition - REMOVES from filteredDeclarations
	    - Everything remaining that wasn't displayed in sections 1-6
	    - `extractUsedButNotAttachedTypes()` takes all remaining items
	    - List size goes to ZERO (should be empty after this)

	 TRACKING MECHANISMS:
	 - `filteredDeclarations`: Master mutable list, progressively shrinks via partitioning in ALL sections
	 - `displayedTypes`: Set tracking what's been shown in sections 1-2
	 - `sharedTypes`: Array of types extracted in section 3
	 - `visited`: Set used internally during tree building

	 - Parameters:
	   - sourceGraph: Source graph to analyze
	   - projectRootPath: Root path of the project for calculating relative paths
	   - onSectionBuilt: Callback invoked with each completed section
	 - Returns: Complete array of all sections
	 */
	nonisolated func buildCategoriesStreaming(
		sourceGraph: SourceGraph,
		projectRootPath: String? = nil,
		onSectionBuilt: @Sendable (CategoriesNode) -> Void
	) -> [CategoriesNode] {
		var filteredDeclarations = filterHighLevelDeclarations(sourceGraph: sourceGraph)
		guard !filteredDeclarations.isEmpty else { return [] }

		let rootDeclaration = filteredDeclarations.first(where: isMainApp) ?? filteredDeclarations.first!
		var visited: Set<Declaration> = []
		var displayedTypes: Set<Declaration> = []
		let typeToReferencers = buildTypeToReferencers(from: filteredDeclarations, sourceGraph: sourceGraph)

		var sections: [CategoriesNode] = []

		// Section 1: Hierarchical Type Dependency Tree
		let section1 = buildHierarchySection(
			rootDeclaration: rootDeclaration,
			typeToReferencers: typeToReferencers,
			viewsOnly: true,
			visited: &visited,
			displayedTypes: &displayedTypes,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section1))
		onSectionBuilt(.section(section1))
		// Remove displayed types from filteredDeclarations after Section 1
		filteredDeclarations.removeAll { displayedTypes.contains($0) }

		// Section 2: View Extensions
		let section2 = buildViewExtensionsSection(
			sourceGraph: sourceGraph,
			typeToReferencers: typeToReferencers,
			visited: &visited,
			displayedTypes: &displayedTypes,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section2))
		onSectionBuilt(.section(section2))
		// Remove displayed types from filteredDeclarations after Section 2
		filteredDeclarations.removeAll { displayedTypes.contains($0) }

		// Section 3: Shared Types
		let sharedTypes = extractSharedTypesNoCommonAncestor(
			typeToReferencers: typeToReferencers,
			rootDeclaration: rootDeclaration,
			displayedTypes: displayedTypes
		)
		let section3 = buildSharedTypesSection(
			sharedTypes,
			typeToReferencers: typeToReferencers,
			displayedTypes: displayedTypes,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section3))
		onSectionBuilt(.section(section3))
		// Remove shared types from filteredDeclarations after Section 3
		filteredDeclarations.removeAll { sharedTypes.contains($0) }

		// Section 4: Orphaned Types
		let orphanedTypes = extractOrphanedTypes(from: &filteredDeclarations, sourceGraph: sourceGraph)
		let section4 = buildDeclarationListSection(
			orphanedTypes,
			sourceGraph: nil,
			title: "ORPHANED TYPES (NO REFERENCES AT ALL). CAN DELETE.",
			section: .orphaned,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section4))
		onSectionBuilt(.section(section4))

		// Section 5: Preview-Only Types
		let previewOnlyTypes = extractPreviewOnlyTypes(
			from: &filteredDeclarations,
			sourceGraph: sourceGraph,
			displayedTypes: Set<Declaration>()
		)
		let section5 = buildDeclarationListSection(
			previewOnlyTypes,
			sourceGraph: nil,
			title: "PREVIEW-ORPHANED TYPES, ONLY REFERENCED BY PREVIEW. CAN DELETE.",
			section: .previewOrphaned,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section5))
		onSectionBuilt(.section(section5))

		// Section 6: Body-Getter Referenced Types
		let onlyBodyGetterTypes = extractOnlyBodyGetterReferencedTypes(
			from: &filteredDeclarations,
			sourceGraph: sourceGraph,
			displayedTypes: displayedTypes
		)
		let section6 = buildDeclarationListSection(
			onlyBodyGetterTypes,
			sourceGraph: nil,
			title: "ONLY REFERENCED BY BODY:GETTER, NOT IN HIERARCHY. HOPEFULLY EMPTY.",
			section: .bodyGetter,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section6))
		onSectionBuilt(.section(section6))

		// Section 7: Used But Not Attached Types
		let usedButNotAttachedTypes = extractUsedButNotAttachedTypes(
			from: &filteredDeclarations,
			displayedTypes: displayedTypes
		)
		let section7 = buildDeclarationListSection(
			usedButNotAttachedTypes,
			sourceGraph: sourceGraph,
			title: "USED BUT NOT ATTACHED TO OUR TYPES. PROBABLY KEEP, BUT CHECK THESE.",
			section: .unattached,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section7))
		onSectionBuilt(.section(section7))

		return sections
	}

	private nonisolated func buildHierarchyNodes(
		rootDeclaration: Declaration,
		relationToParent: RelationshipType?,
		typeToReferencers: [Declaration: [String: Relation]],
		viewsOnly: Bool,
		parentSourceFile: SourceFile?,
		visited: inout Set<Declaration>,
		displayedTypes: inout Set<Declaration>,
		sourceGraph: SourceGraph?,
		projectRootPath: String?,
		outputNodes: inout [CategoriesNode]
	) {
		if !displayedTypes.contains(rootDeclaration) {
			displayedTypes.insert(rootDeclaration)
		}

		let children: [Declaration] = typeToReferencers.compactMap { childDeclaration, parentToRelation -> (
			Declaration,
			Location
		)? in
			if let relation = parentToRelation[rootDeclaration.name ?? ""] {
				if !displayedTypes.contains(childDeclaration) {
					return (childDeclaration, relation.location)
				}
			}
			return nil
		}.sorted(by: { $0.1 < $1.1 })
			.map(\.0)

		let shouldDisplayThisNode = !viewsOnly || conformsToView(rootDeclaration)

		if shouldDisplayThisNode {
			if let node = buildDeclarationNode(
				rootDeclaration,
				relationToParent: relationToParent,
				typeToReferencers: typeToReferencers,
				viewsOnly: false,
				parentSourceFile: parentSourceFile,
				visited: &visited,
				displayedTypes: &displayedTypes,
				sourceGraph: sourceGraph,
				projectRootPath: projectRootPath
			) {
				outputNodes.append(.declaration(node))
			}
		} else {
			visited.insert(rootDeclaration)

			for child in children {
				if !displayedTypes.contains(child) {
					if let relation = typeToReferencers[child]?[rootDeclaration.name ?? ""] {
						buildHierarchyNodes(
							rootDeclaration: child,
							relationToParent: relation.relationType,
							typeToReferencers: typeToReferencers,
							viewsOnly: viewsOnly,
							parentSourceFile: rootDeclaration.location.file,
							visited: &visited,
							displayedTypes: &displayedTypes,
							sourceGraph: sourceGraph,
							projectRootPath: projectRootPath,
							outputNodes: &outputNodes
						)
					}
				}
			}
		}
	}

	private nonisolated func buildHierarchySection(
		rootDeclaration: Declaration,
		typeToReferencers: [Declaration: [String: Relation]],
		viewsOnly: Bool,
		visited: inout Set<Declaration>,
		displayedTypes: inout Set<Declaration>,
		projectRootPath: String?
	) -> SectionNode {
		var children: [CategoriesNode] = []

		buildHierarchyNodes(
			rootDeclaration: rootDeclaration,
			relationToParent: nil,
			typeToReferencers: typeToReferencers,
			viewsOnly: viewsOnly,
			parentSourceFile: nil,
			visited: &visited,
			displayedTypes: &displayedTypes,
			sourceGraph: nil,
			projectRootPath: projectRootPath,
			outputNodes: &children
		)

		return SectionNode(
			id: .hierarchy,
			title: "HIERARCHICAL TYPE DEPENDENCY TREE",
			children: children
		)
	}

	private nonisolated func buildViewExtensionsSection(
		sourceGraph: SourceGraph,
		typeToReferencers: [Declaration: [String: Relation]],
		visited: inout Set<Declaration>,
		displayedTypes: inout Set<Declaration>,
		projectRootPath: String?
	) -> SectionNode {
		let protocolExtensions = sourceGraph.declarations(ofKind: .extensionProtocol)

		let viewExtensions = protocolExtensions.filter { extDecl in
			let hasViewReference = extDecl.references.contains { (ref: Reference) in
				ref.name == "View" && ref.declarationKind == .protocol
			}
			return hasViewReference
		}
		.sorted(by: { $0.location < $1.location })

		var children: [CategoriesNode] = []

		if !viewExtensions.isEmpty {
			var rootChildren: [CategoriesNode] = []

			for extDecl in viewExtensions {
				let extensionFunctions = extDecl.declarations
					.filter(\.kind.isFunctionKind)
					.sorted(by: { $0.location < $1.location })

				if !extensionFunctions.isEmpty {
					var augmentedMapping = typeToReferencers

					for funcDecl in extensionFunctions {
						for ref in funcDecl.references {
							if let referencedDecl = sourceGraph.declaration(withUsr: ref.usr),
							   highLevelKinds.contains(referencedDecl.kind) {
								let relation = Relation(
									relationType: .call,
									location: ref.location,
									declaration: funcDecl
								)
								var parents = augmentedMapping[referencedDecl] ?? [:]
								parents[funcDecl.name ?? "function"] = relation
								augmentedMapping[referencedDecl] = parents
							}
						}
					}

					for funcDecl in extensionFunctions {
						let isViewModifierEmbedder = isViewModifierEmbeddingFunction(funcDecl, sourceGraph: sourceGraph)
						let originalName = funcDecl.name ?? "unnamed"
						let displayName = isViewModifierEmbedder ? "\(originalName) [embeds ViewModifier]" :
							originalName

						if let functionNode = buildDeclarationNode(
							funcDecl,
							relationToParent: nil,
							typeToReferencers: augmentedMapping,
							viewsOnly: false,
							parentSourceFile: nil,
							visited: &visited,
							displayedTypes: &displayedTypes,
							sourceGraph: sourceGraph,
							projectRootPath: projectRootPath,
							customDisplayName: displayName
						) {
							rootChildren.append(.declaration(functionNode))
						}
					}
				}
			}

			children.append(.syntheticRoot(SyntheticRootNode(
				id: "synthetic-view-root",
				title: "View",
				icon: .emoji("🖼️"),
				children: rootChildren
			)))
		}

		return SectionNode(
			id: .viewExtensions,
			title: "VIEW EXTENSIONS. FOR VIEWMODIFIERS AND ADVANCED SWIFTUI TECHNIQUES.",
			children: children
		)
	}

	private nonisolated func buildSharedTypesSection(
		_ sharedTypes: [Declaration],
		typeToReferencers: [Declaration: [String: Relation]],
		displayedTypes _: Set<Declaration>,
		projectRootPath: String?
	) -> SectionNode {
		var children: [CategoriesNode] = []

		for sharedType in sharedTypes.sorted(by: { $0.name ?? "" < $1.name ?? "" }) {
			var localVisited = Set<Declaration>()
			var localDisplayed = Set<Declaration>()

			if let node = buildDeclarationNode(
				sharedType,
				relationToParent: nil,
				typeToReferencers: typeToReferencers,
				viewsOnly: false,
				parentSourceFile: nil,
				visited: &localVisited,
				displayedTypes: &localDisplayed,
				sourceGraph: nil,
				projectRootPath: projectRootPath
			) {
				children.append(.declaration(node))
			}
		}

		return SectionNode(
			id: .shared,
			title: "SHARED TYPES WITH NO COMMON ANCESTOR",
			children: children
		)
	}

	private nonisolated func buildDeclarationListSection(
		_ declarations: [Declaration],
		sourceGraph: SourceGraph?,
		title: String,
		section: CategorySection,
		projectRootPath: String?
	) -> SectionNode {
		var children: [CategoriesNode] = []

		for type in declarations.sorted(by: { $0.location < $1.location }) {
			let referencerNames: [String] = if let sourceGraph {
				referencingDeclarations(for: type, in: sourceGraph)
					.filter { $0.name != "makePreview()" }
					.map(\.debugString)
					.uniqued()
			} else {
				[]
			}

			let typeIcon = getTypeIcon(for: type)
			let name = type.name ?? "unnamed"
			let locationInfo = buildLocationInfo(
				for: type,
				relationToParent: nil,
				parentSourceFile: nil,
				childrenLineCount: 0,
				projectRootPath: projectRootPath
			)

			let folderIndicator: TreeIcon? = isViewInOwnFolder(type) ? .systemImage("folder") : nil

			let nodeId = "\(type.kind.rawValue)-\(name)-\(type.location.file.path.string):\(type.location.line)"
			let node = DeclarationNode(
				id: nodeId,
				folderIndicator: folderIndicator,
				typeIcon: typeIcon,
				isView: conformsToView(type),
				displayName: name,
				conformances: "",
				relationship: nil,
				locationInfo: locationInfo,
				referencerInfo: referencerNames.isEmpty ? nil : referencerNames,
				children: []
			)

			children.append(.declaration(node))
		}

		return SectionNode(
			id: section,
			title: title,
			children: children
		)
	}

	private nonisolated func buildDeclarationNode(
		_ declaration: Declaration,
		relationToParent: RelationshipType?,
		typeToReferencers: [Declaration: [String: Relation]],
		viewsOnly: Bool,
		parentSourceFile: SourceFile?,
		visited: inout Set<Declaration>,
		displayedTypes: inout Set<Declaration>,
		sourceGraph: SourceGraph?,
		projectRootPath: String?,
		customDisplayName: String? = nil
	) -> DeclarationNode? {
		if !displayedTypes.contains(declaration) {
			displayedTypes.insert(declaration)
		}

		let name = customDisplayName ?? (declaration.name ?? "")
		var conforms: String = Array(Set(declaration.immediateInheritedTypeReferences.compactMap(\.name))).sorted()
			.joined(separator: ", ")

		let typeIcon = getTypeIcon(for: declaration)
		let folderIndicator: TreeIcon? = isViewInOwnFolder(declaration) ? .systemImage("folder") : nil

		if conformsToView(declaration) {
			conforms = ""
		}

		let relationshipType: RelationshipType? = if conformsToView(declaration) && relationToParent == .subview ||
			relationToParent?.rawValue == nil {
			nil
		} else {
			relationToParent
		}

		let children: [Declaration] = typeToReferencers.compactMap { childDeclaration, parentToRelation -> (
			Declaration,
			Location
		)? in
			if let relation = parentToRelation[declaration.name ?? ""] {
				if !displayedTypes.contains(childDeclaration) {
					return (childDeclaration, relation.location)
				}
			}
			return nil
		}.sorted(by: { $0.1 < $1.1 })
			.map(\.0)

		let childrenLineCount = children.reduce(0) { $0 + ($1.location.endLine ?? 0) - $1.location.line + 1 }

		if viewsOnly, !conformsToView(declaration) {
			visited.insert(declaration)
			return nil
		}

		let locationInfo = buildLocationInfo(
			for: declaration,
			relationToParent: relationToParent,
			parentSourceFile: parentSourceFile,
			childrenLineCount: childrenLineCount,
			projectRootPath: projectRootPath
		)

		visited.insert(declaration)

		var childNodes: [CategoriesNode] = []
		for child in children {
			if !displayedTypes.contains(child) {
				if let relation = typeToReferencers[child]?[declaration.name ?? ""] {
					if let childNode = buildDeclarationNode(
						child,
						relationToParent: relation.relationType,
						typeToReferencers: typeToReferencers,
						viewsOnly: viewsOnly,
						parentSourceFile: declaration.location.file,
						visited: &visited,
						displayedTypes: &displayedTypes,
						sourceGraph: sourceGraph,
						projectRootPath: projectRootPath
					) {
						childNodes.append(.declaration(childNode))
					}
				}
			}
		}

		let nodeId = "\(declaration.kind.rawValue)-\(name)-\(declaration.location.file.path.string):\(declaration.location.line)"
		return DeclarationNode(
			id: nodeId,
			folderIndicator: folderIndicator,
			typeIcon: typeIcon,
			isView: conformsToView(declaration),
			displayName: name,
			conformances: conforms.isEmpty ? "" : ": \(conforms)",
			relationship: relationshipType,
			locationInfo: locationInfo,
			referencerInfo: nil,
			children: childNodes
		)
	}

	private nonisolated func getTypeIcon(for declaration: Declaration) -> TreeIcon {
		DeclarationIconHelper.typeIcon(for: declaration)
	}

	private nonisolated func isViewInOwnFolder(_ declaration: Declaration) -> Bool {
		guard DeclarationIconHelper.conformsToView(declaration), let declName = declaration.name else {
			return false
		}
		let filePath = declaration.location.file.path.string
		let fileNameWithoutExt = ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension
		let folderName = ((filePath as NSString).deletingLastPathComponent as NSString).lastPathComponent
		return declName == fileNameWithoutExt && declName == folderName
	}

	private nonisolated func buildLocationInfo(
		for declaration: Declaration,
		relationToParent: RelationshipType?,
		parentSourceFile: SourceFile?,
		childrenLineCount: Int,
		projectRootPath: String?
	) -> LocationInfo {
		let lineSpan = (declaration.location.endLine ?? 0) - declaration.location.line
		let fileName = declaration.location.file.path.lastComponent?.description
		let line = declaration.location.line
		let endLine = declaration.location.endLine
		let fullPath = declaration.location.file.path.string

		// Calculate relative path from project root
		let relativePath: String? = if let projectRoot = projectRootPath, fullPath.hasPrefix(projectRoot) {
			String(fullPath.dropFirst(projectRoot.count + 1))
		} else {
			nil
		}

		/* Priority 1: Size warnings in same file (most actionable) */
		if relationToParent != nil, relationToParent != .embed,
		   declaration.location.file == parentSourceFile {
			if lineSpan + childrenLineCount >= 200 {
				return LocationInfo(
					type: .tooBigForSameFile,
					icon: .emoji("🆘"),
					fileName: fileName,
					relativePath: relativePath,
					line: line,
					endLine: endLine,
					warningText: "\(lineSpan) lines + \(childrenLineCount) children's lines"
				)
			} else if lineSpan > 200 {
				return LocationInfo(
					type: .tooBigForSameFile,
					icon: .emoji("🆘"),
					fileName: fileName,
					relativePath: relativePath,
					line: line,
					endLine: endLine,
					warningText: "\(lineSpan) lines"
				)
			}
		}

		/* Priority 2: Swift language nesting */
		if declaration.parent != nil {
			return LocationInfo(
				type: .swiftNested,
				icon: .emoji("📎"),
				fileName: nil,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				warningText: nil
			)
		}

		/* Priority 3: Same-file semantic relationship */
		if relationToParent != nil, relationToParent != .embed,
		   declaration.location.file == parentSourceFile {
			return LocationInfo(
				type: .sameFile,
				icon: .emoji("🔼"),
				fileName: nil,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				warningText: nil
			)
		}

		/* Priority 4+: Separate file logic */
		let inSameFile: Bool = declaration.name == declaration.location.file.path.lastComponent
			.map { ($0.description as NSString).deletingPathExtension }

		if lineSpan > 100, inSameFile {
			return LocationInfo(
				type: .separateFileGood,
				icon: .emoji("✅"),
				fileName: fileName,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				warningText: nil
			)
		} else if children(of: declaration).count >= 1, inSameFile {
			return LocationInfo(
				type: .separateFileGood,
				icon: .emoji("✅"),
				fileName: fileName,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				warningText: nil
			)
		} else if inSameFile {
			return LocationInfo(
				type: .separateFileTooSmall,
				icon: .emoji("😒"),
				fileName: fileName,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				warningText: "too small for separate file"
			)
		} else {
			return LocationInfo(
				type: .separateFileNameMismatch,
				icon: .emoji("🛑"),
				// icon: .systemImage("notequal.circle.fill"),
				fileName: fileName,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				warningText: "separate file name mismatch"
			)
		}
	}

	private nonisolated func children(of declaration: Declaration) -> [Declaration] {
		Array(declaration.declarations)
	}
}

private extension Declaration {
	nonisolated var firstNameComponent: String {
		name?.components(separatedBy: ".").first ?? ""
	}
}

private extension Declaration {
	nonisolated func locString(includeFilename: Bool = true) -> String {
		let fileComponent = location.file.path.lastComponent ?? "nil"
		let file = "\(fileComponent)"
		let line = location.line
		let endLine: String = location.endLine.map { ":\($0)" } ?? ""

		return "\(includeFilename ? file : ""):\(line)\(endLine)"
	}

	/// Returns a debug string with info (kind name [file:line])
	nonisolated var debugString: String {
		let name = name ?? ""
		let kind = kind.icon
		return "\(kind) \(name) \(locString())"
	}
}

private extension Sequence {
	/// Returns two arrays: elements matching `predicate` and elements not matching.
	/// Preserves the original order of elements.
	nonisolated func partitioned(by predicate: (Element) throws -> Bool) rethrows -> ([Element], [Element]) {
		var matches: [Element] = []
		var nonMatches: [Element] = []
		for element in self {
			if try predicate(element) {
				matches.append(element)
			} else {
				nonMatches.append(element)
			}
		}
		return (matches, nonMatches)
	}
}
