//
//  Dumper.swift
//  Treeswift
//
//  Created by Dan Wood on 10/10/25.
//

// @preconcurrency: SourceGraph library was written before Swift 6 concurrency
// This suppresses warnings about Sendable conformance for types from this module
// Note: Location and Declaration classes have been marked @unchecked Sendable in PeripherySource
@preconcurrency import SourceGraph
import SystemPackage
import Foundation
import XcodeProj
import Extensions

final class Dumper: Sendable {

	nonisolated(unsafe) private let highLevelKinds: Set<Declaration.Kind> = [.class, .struct, .enum, .protocol, .extensionClass, .extensionStruct, .extensionEnum, .extensionProtocol]

	nonisolated init() {}

	private struct Relation {
		let relationType: RelationshipType
		let location: Location
		let declaration: Declaration
	}

	// MARK: - Helper functions

	nonisolated private func isEnvironmentRelated(_ declaration: Declaration) -> Bool {
		let environmentAttributes = ["EnvironmentObject", "Environment"]
		// Check declaration attributes
		if declaration.attributes.contains(where: { environmentAttributes.contains($0) }) {
			return true
		}
		// Check inheritance (covers e.g. property wrappers in protocols)
		if declaration.immediateInheritedTypeReferences.contains(where: { ref in
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

	nonisolated private func conformsToView(_ decl: Declaration) -> Bool {
		return DeclarationIconHelper.conformsToView(decl)
	}

	nonisolated private func isSubviewPattern(parent: Declaration, child: Declaration, ref _: Reference?) -> Bool {
		// Return true if both parent and child conform to View
		let isChildView = conformsToView(child)
		let isParentView = conformsToView(parent)
		if isParentView && isChildView {
			return true
		}
		return false
	}

	nonisolated private func isPreview(_ decl: Declaration) -> Bool {
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

	nonisolated private func isMainApp(_ decl: Declaration) -> Bool {
		return DeclarationIconHelper.isMainApp(decl)
	}

	nonisolated private func getRelationshipType(graph: SourceGraph, child: Declaration, parent: Declaration) -> RelationshipType {
		let parentReferences = graph.references(to: child)

		// Added: Scan for variableInitFunctionCall references
		if parentReferences.contains(where: { $0.role == .variableInitFunctionCall }) {
			return .prop
		}

		// Check if child is nested in parent
		if child.parent == parent {
			return .embed
		}

		let sameFileReferences = parentReferences.filter { ref in
			// Check if this reference is in the same file as the parent
			ref.location.file.path == parent.location.file.path
		}

		if !sameFileReferences.isEmpty {

			// Check if parent uses child in a constructor call or as a struct reference
			let hasConstructorReference = sameFileReferences.contains { ref in
				ref.kind == .functionConstructor || ref.kind == .struct
			}
			if hasConstructorReference {

				// Check if this is a subview relationship (SwiftUI pattern)
				let hasSubviewReference = sameFileReferences.contains { ref in
					let isSubview = isSubviewPattern(parent: parent, child: child, ref: ref)
					return isSubview
				}

				if hasSubviewReference {
					return .subview
				}
				return .constructs
			}

			// Check if parent has a property of child type
			let hasPropertyReference = sameFileReferences.contains { ref in
				ref.kind == .varInstance || ref.kind == .varGlobal
			}
			if hasPropertyReference {
				return .prop
			}

			// Check if parent uses child as a parameter type
			let hasParameterReference = sameFileReferences.contains { ref in
				ref.kind == .functionMethodInstance
			}
			if hasParameterReference {
				return .param
			}

			// Check if parent uses child as a local variable type
			let hasLocalVarReference = sameFileReferences.contains { ref in
				ref.kind == .varLocal
			}
			if hasLocalVarReference {
				return .local
			}

			// Check if parent uses child in a static property/method
			let hasStaticReference = sameFileReferences.contains { ref in
				ref.kind == .varStatic || ref.kind == .functionMethodStatic
			}
			if hasStaticReference {
				return .staticMember
			}

			// Check if parent uses child in a method call
			let hasMethodCallReference = sameFileReferences.contains { ref in
				ref.kind == .functionMethodInstance || ref.kind == .functionMethodStatic
			}
			if hasMethodCallReference {
				return .call
			}

			// Check if parent uses child in a type annotation
			let hasTypeAnnotationReference = sameFileReferences.contains { ref in
				ref.kind == .varInstance || ref.kind == .varGlobal || ref.kind == .varLocal
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


	nonisolated private func getAncestorChain(_ decl: Declaration) -> Set<Declaration> {
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
	nonisolated private func filterHighLevelDeclarations(graph: SourceGraph) -> [Declaration] {
		let projectModules = Set(graph.indexedSourceFiles.flatMap { $0.modules })
		return graph.declarations(ofKinds: highLevelKinds)
			.filter { !isPreview($0) }
			.filter { !$0.kind.isExtensionKind || projectModules.contains($0.firstNameComponent) }
			.sorted(by: { $0.location < $1.location })		// TEMP sort for reproducibility
	}

	/// Finds orphaned types with no references and removes them from the declarations array.
	nonisolated private func extractOrphanedTypes(from declarations: inout [Declaration], graph: SourceGraph) -> [Declaration] {
		let (orphanedTypes, remaining) = declarations.partitioned { type in
			!isMainApp(type) && graph.references(to: type).isEmpty
		}
		declarations = remaining
		return orphanedTypes
	}

	/// Finds types whose only references are from getter:body and removes them from the declarations array.
	nonisolated private func extractOnlyBodyGetterReferencedTypes(
		from declarations: inout [Declaration],
		graph: SourceGraph,
		displayedTypes: Set<Declaration>
	) -> [Declaration] {
		let (onlyBodyGetterTypes, remaining) = declarations.partitioned { type in
			guard !displayedTypes.contains(type), !isMainApp(type) else { return false }
			let referencingDecls = referencingDeclarations(for: type, in: graph)
			return !isMainApp(type) &&
			!referencingDecls.isEmpty &&
			referencingDecls.allSatisfy { ref in
				ref.kind == .functionAccessorGetter && ref.name == "getter:body"
			}
		}
		declarations = remaining
		return onlyBodyGetterTypes
	}


	/// Extracts preview-only types and removes them from the declarations array.
	nonisolated private func extractPreviewOnlyTypes(
		from declarations: inout [Declaration],
		graph: SourceGraph,
		displayedTypes: Set<Declaration>
	) -> [Declaration] {
		let (previewOnlyTypes, remaining) = declarations.partitioned { type in
			guard !displayedTypes.contains(type), !isMainApp(type) else { return false }
			let referencingDecls = referencingDeclarations(for: type, in: graph)
			guard !referencingDecls.isEmpty else { return false }
			// Check if all references come from static methods named exactly "makePreview()"
			return referencingDecls.allSatisfy { ref in
				ref.kind.rawValue.contains("static") && ref.name == "makePreview()"
			}
		}
		declarations = remaining
		return previewOnlyTypes
	}

	/// Given a type and a graph, returns all declarations that reference this type.
	nonisolated private func referencingDeclarations(for type: Declaration, in graph: SourceGraph) -> [Declaration] {
		let references = graph.references(to: type).sorted { $0.location < $1.location }

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
	nonisolated private func buildTypeToReferencers(from declarations: [Declaration], graph: SourceGraph) -> [Declaration: [String: Relation]] {

		func findRelevantReferencingType(ref: Reference, declaration: Declaration, highLevelKinds: Set<Declaration.Kind>, graph: SourceGraph) -> Declaration? {
			return sequence(first: ref.parent) { $0?.parent }
				.compactMap { $0 }
				.first{
					highLevelKinds.contains($0.kind) &&
					$0 != declaration &&
					!isPreview($0) &&
					!isEnvironmentRelated($0)
				}
		}

		/// Build referencers dictionary for a given declaration that is not embedded.
		func buildReferencers(for declaration: Declaration, in graph: SourceGraph) -> [String: Relation] {
			let references: [Reference] = graph.references(to: declaration).sorted { $0.location < $1.location }

			return references.reduce(into: [String: Relation]()) { referencers, ref in
				if let referencingType: Declaration = findRelevantReferencingType(ref: ref, declaration: declaration, highLevelKinds: highLevelKinds, graph: graph) {
					if !referencingType.kind.isExtensionKind {
						let relationshipType = getRelationshipType(graph: graph, child: declaration, parent: referencingType)
						referencers[referencingType.name ?? ""] = Relation(relationType: relationshipType, location: ref.location, declaration: referencingType)
					} else {
						// Try to find the extended type and add it to referencers instead
						if let extendedTypeName = referencingType.name {
							let extendedTypeDeclarations = graph.allDeclarations.filter { decl in
								decl.name == extendedTypeName && !decl.kind.isExtensionKind
							}
							for extDecl in extendedTypeDeclarations {
								let relationshipType = getRelationshipType(graph: graph, child: declaration, parent: extDecl)
								referencers[extDecl.name ?? ""] = Relation(relationType: relationshipType, location: ref.location, declaration: extDecl)
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
				typeToReferencers[declaration] = [ name : relation ]
			} else {
				typeToReferencers[declaration] = buildReferencers(for: declaration, in: graph)
			}
		}
	}
	/// Finds types shared by multiple referencers without a common ancestor.
	nonisolated private func extractSharedTypesNoCommonAncestor(typeToReferencers: [Declaration: [String: Relation]], rootDeclaration: Declaration, displayedTypes: Set<Declaration>) -> [Declaration] {

		func hasCommonAncestors(_ referencers: [Declaration], rootDeclaration: Declaration) -> Bool {
			for i in 0..<referencers.count {
				for j in (i+1)..<referencers.count {
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
					let referencers = referencersMap.values.map { $0.declaration }
				if !hasCommonAncestors(referencers, rootDeclaration: rootDeclaration) {
					if !displayedTypes.contains(sharedType) {
						acc.append(sharedType)
					}
				}
			}
		}
	}
	/// Finds types that are used but not attached to our types and not yet displayed.
	nonisolated private func extractUsedButNotAttachedTypes(from declarations: inout [Declaration], displayedTypes: Set<Declaration>) -> [Declaration] {
		let (usedButNotAttached, remaining) = declarations.partitioned { !displayedTypes.contains($0) && !isMainApp($0) }
		declarations = remaining
		return usedButNotAttached
	}
	/// Checks if a function embeds a ViewModifier by looking for the .modifier() pattern
	nonisolated private func isViewModifierEmbeddingFunction(_ funcDecl: Declaration, graph _: SourceGraph) -> Bool {
		// Look for references to "modifier" method calls within this function
		let hasModifierCall = funcDecl.references.contains { ref in
			ref.name == "modifier" && ref.kind == .functionMethodInstance
		}

		// Also check for "modifier(_:)" which is the full method signature
		let hasModifierCallWithParam = funcDecl.references.contains { ref in
			ref.name == "modifier(_:)" && ref.kind == .functionMethodInstance
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
	  - graph: Source graph to analyze
	  - projectRootPath: Root path of the project for calculating relative paths
	  - onSectionBuilt: Callback invoked with each completed section
	- Returns: Complete array of all sections
	*/
	nonisolated func buildCategoriesStreaming(
		graph: SourceGraph,
		projectRootPath: String? = nil,
		onSectionBuilt: @Sendable (CategoriesNode) -> Void
	) -> [CategoriesNode] {
		var filteredDeclarations = filterHighLevelDeclarations(graph: graph)
		guard !filteredDeclarations.isEmpty else { return [] }

		let rootDeclaration = filteredDeclarations.first(where: isMainApp) ?? filteredDeclarations.first!
		var visited: Set<Declaration> = []
		var displayedTypes: Set<Declaration> = []
		let typeToReferencers = buildTypeToReferencers(from: filteredDeclarations, graph: graph)

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
			graph: graph,
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
		let orphanedTypes = extractOrphanedTypes(from: &filteredDeclarations, graph: graph)
		let section4 = buildDeclarationListSection(
			orphanedTypes,
			graph: nil,
			title: "ORPHANED TYPES (NO REFERENCES AT ALL). CAN DELETE.",
			section: .orphaned,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section4))
		onSectionBuilt(.section(section4))

		// Section 5: Preview-Only Types
		let previewOnlyTypes = extractPreviewOnlyTypes(from: &filteredDeclarations, graph: graph, displayedTypes: Set<Declaration>())
		let section5 = buildDeclarationListSection(
			previewOnlyTypes,
			graph: nil,
			title: "PREVIEW-ORPHANED TYPES, ONLY REFERENCED BY PREVIEW. CAN DELETE.",
			section: .previewOrphaned,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section5))
		onSectionBuilt(.section(section5))

		// Section 6: Body-Getter Referenced Types
		let onlyBodyGetterTypes = extractOnlyBodyGetterReferencedTypes(from: &filteredDeclarations, graph: graph, displayedTypes: displayedTypes)
		let section6 = buildDeclarationListSection(
			onlyBodyGetterTypes,
			graph: nil,
			title: "ONLY REFERENCED BY BODY:GETTER, NOT IN HIERARCHY. HOPEFULLY EMPTY.",
			section: .bodyGetter,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section6))
		onSectionBuilt(.section(section6))

		// Section 7: Used But Not Attached Types
		let usedButNotAttachedTypes = extractUsedButNotAttachedTypes(from: &filteredDeclarations, displayedTypes: displayedTypes)
		let section7 = buildDeclarationListSection(
			usedButNotAttachedTypes,
			graph: graph,
			title: "USED BUT NOT ATTACHED TO OUR TYPES. PROBABLY KEEP, BUT CHECK THESE.",
			section: .unattached,
			projectRootPath: projectRootPath
		)
		sections.append(.section(section7))
		onSectionBuilt(.section(section7))

		return sections
	}

	nonisolated private func buildHierarchyNodes(
		rootDeclaration: Declaration,
		relationToParent: RelationshipType?,
		typeToReferencers: [Declaration: [String: Relation]],
		viewsOnly: Bool,
		parentSourceFile: SourceFile?,
		visited: inout Set<Declaration>,
		displayedTypes: inout Set<Declaration>,
		graph: SourceGraph?,
		projectRootPath: String?,
		outputNodes: inout [CategoriesNode]
	) {
		if !displayedTypes.contains(rootDeclaration) {
			displayedTypes.insert(rootDeclaration)
		}

		let children: [Declaration] = typeToReferencers.compactMap { (childDeclaration, parentToRelation) -> (Declaration, Location)? in
			if let relation = parentToRelation[rootDeclaration.name ?? ""] {
				if !displayedTypes.contains(childDeclaration) {
					return (childDeclaration, relation.location)
				}
			}
			return nil
		}.sorted(by: { $0.1 < $1.1 })
			.map { $0.0 }

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
				graph: graph,
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
							graph: graph,
							projectRootPath: projectRootPath,
							outputNodes: &outputNodes
						)
					}
				}
			}
		}
	}

	nonisolated private func buildHierarchySection(
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
			graph: nil,
			projectRootPath: projectRootPath,
			outputNodes: &children
		)

		return SectionNode(
			id: .hierarchy,
			title: "HIERARCHICAL TYPE DEPENDENCY TREE",
			children: children
		)
	}

	nonisolated private func buildViewExtensionsSection(
		graph: SourceGraph,
		typeToReferencers: [Declaration: [String: Relation]],
		visited: inout Set<Declaration>,
		displayedTypes: inout Set<Declaration>,
		projectRootPath: String?
	) -> SectionNode {
		let protocolExtensions = graph.declarations(ofKind: .extensionProtocol)

		let viewExtensions = protocolExtensions.filter { extDecl in
			let hasViewReference = extDecl.references.contains { ref in
				ref.name == "View" && ref.kind == .protocol
			}
			return hasViewReference
		}
		.sorted(by: { $0.location < $1.location })

		var children: [CategoriesNode] = []

		if !viewExtensions.isEmpty {
			var rootChildren: [CategoriesNode] = []

			for extDecl in viewExtensions {
				let extensionFunctions = extDecl.declarations
					.filter { $0.kind.isFunctionKind }
					.sorted(by: { $0.location < $1.location })

				if !extensionFunctions.isEmpty {
					var augmentedMapping = typeToReferencers

					for funcDecl in extensionFunctions {
						for ref in funcDecl.references {
							if let referencedDecl = graph.declaration(withUsr: ref.usr),
							   highLevelKinds.contains(referencedDecl.kind) {
								let relation = Relation(relationType: .call, location: ref.location, declaration: funcDecl)
								var parents = augmentedMapping[referencedDecl] ?? [:]
								parents[funcDecl.name ?? "function"] = relation
								augmentedMapping[referencedDecl] = parents
							}
						}
					}

					for funcDecl in extensionFunctions {
						let isViewModifierEmbedder = isViewModifierEmbeddingFunction(funcDecl, graph: graph)
						let originalName = funcDecl.name ?? "unnamed"
						let displayName = isViewModifierEmbedder ? "\(originalName) [embeds ViewModifier]" : originalName

						if let functionNode = buildDeclarationNode(
							funcDecl,
							relationToParent: nil,
							typeToReferencers: augmentedMapping,
							viewsOnly: false,
							parentSourceFile: nil,
							visited: &visited,
							displayedTypes: &displayedTypes,
							graph: graph,
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

	nonisolated private func buildSharedTypesSection(
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
				graph: nil,
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

	nonisolated private func buildDeclarationListSection(
		_ declarations: [Declaration],
		graph: SourceGraph?,
		title: String,
		section: CategorySection,
		projectRootPath: String?
	) -> SectionNode {
		var children: [CategoriesNode] = []

		for type in declarations.sorted(by: { $0.location < $1.location }) {
			let referencerNames: [String] = if let graph = graph {
				referencingDeclarations(for: type, in: graph)
					.filter { $0.name != "makePreview()" }
					.map { $0.debugString }
					.uniqued()
			} else {
				[]
			}

			let typeIcon = getTypeIcon(for: type)
			let name = type.name ?? "unnamed"
			let locationInfo = buildLocationInfo(for: type, relationToParent: nil, parentSourceFile: nil, childrenLineCount: 0, projectRootPath: projectRootPath)

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

	nonisolated private func buildDeclarationNode(
		_ declaration: Declaration,
		relationToParent: RelationshipType?,
		typeToReferencers: [Declaration: [String: Relation]],
		viewsOnly: Bool,
		parentSourceFile: SourceFile?,
		visited: inout Set<Declaration>,
		displayedTypes: inout Set<Declaration>,
		graph: SourceGraph?,
		projectRootPath: String?,
		customDisplayName: String? = nil
	) -> DeclarationNode? {
		if !displayedTypes.contains(declaration) {
			displayedTypes.insert(declaration)
		}

		let name = customDisplayName ?? (declaration.name ?? "")
		var conforms: String = Array(Set(declaration.immediateInheritedTypeReferences.compactMap { $0.name })).sorted().joined(separator: ", ")

		let typeIcon = getTypeIcon(for: declaration)
		let folderIndicator: TreeIcon? = isViewInOwnFolder(declaration) ? .systemImage("folder") : nil

		if conformsToView(declaration) {
			conforms = ""
		}

		let relationshipType: RelationshipType?
		if conformsToView(declaration) && relationToParent == .subview || relationToParent?.rawValue == nil {
			relationshipType = nil
		} else {
			relationshipType = relationToParent
		}

		let children: [Declaration] = typeToReferencers.compactMap { (childDeclaration, parentToRelation) -> (Declaration, Location)? in
			if let relation = parentToRelation[declaration.name ?? ""] {
				if !displayedTypes.contains(childDeclaration) {
					return (childDeclaration, relation.location)
				}
			}
			return nil
		}.sorted(by: { $0.1 < $1.1 })
			.map { $0.0 }

		let childrenLineCount = children.reduce(0) { $0 + ($1.location.endLine ?? 0) - $1.location.line + 1 }

		if viewsOnly && !conformsToView(declaration) {
			visited.insert(declaration)
			return nil
		}

		let locationInfo = buildLocationInfo(for: declaration, relationToParent: relationToParent, parentSourceFile: parentSourceFile, childrenLineCount: childrenLineCount, projectRootPath: projectRootPath)

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
						graph: graph,
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

	nonisolated private func getTypeIcon(for declaration: Declaration) -> TreeIcon {
		return DeclarationIconHelper.typeIcon(for: declaration)
	}

	nonisolated private func isViewInOwnFolder(_ declaration: Declaration) -> Bool {
		guard DeclarationIconHelper.conformsToView(declaration), let declName = declaration.name else {
			return false
		}
		let filePath = declaration.location.file.path.string
		let fileNameWithoutExt = ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension
		let folderName = ((filePath as NSString).deletingLastPathComponent as NSString).lastPathComponent
		return declName == fileNameWithoutExt && declName == folderName
	}

	nonisolated private func buildLocationInfo(for declaration: Declaration, relationToParent: RelationshipType?, parentSourceFile: SourceFile?, childrenLineCount: Int, projectRootPath: String?) -> LocationInfo {
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

		let blackSquares = ["⬛", "◼", "▪", "·"]
		let sizeIndicator: String
		if lineSpan > 100 {
			sizeIndicator = blackSquares[0]
		} else if lineSpan > 75 {
			sizeIndicator = blackSquares[1]
		} else if lineSpan > 50 {
			sizeIndicator = blackSquares[2]
		} else if lineSpan > 25 {
			sizeIndicator = blackSquares[3]
		} else {
			sizeIndicator = ""
		}

		/* Priority 1: Size warnings in same file (most actionable) */
		if relationToParent != nil && relationToParent != .embed
		&& declaration.location.file == parentSourceFile {
			if lineSpan + childrenLineCount >= 200 {
				return LocationInfo(
					type: .tooBigForSameFile,
					icon: .emoji("🆘"),
					fileName: fileName,
					relativePath: relativePath,
					line: line,
					endLine: endLine,
					sizeIndicator: sizeIndicator,
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
					sizeIndicator: sizeIndicator,
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
				sizeIndicator: sizeIndicator,
				warningText: nil
			)
		}

		/* Priority 3: Same-file semantic relationship */
		if relationToParent != nil && relationToParent != .embed
		&& declaration.location.file == parentSourceFile {
			return LocationInfo(
				type: .sameFile,
				icon: .emoji("🔼"),
				fileName: nil,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				sizeIndicator: sizeIndicator,
				warningText: nil
			)
		}

		/* Priority 4+: Separate file logic */
		let inSameFile: Bool = declaration.name == declaration.location.file.path.lastComponent.map { ($0.description as NSString).deletingPathExtension }

		if lineSpan > 100 && inSameFile {
			return LocationInfo(
				type: .separateFileGood,
				icon: .emoji("✅"),
				fileName: fileName,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				sizeIndicator: sizeIndicator,
				warningText: nil
			)
		} else if children(of: declaration).count >= 1 && inSameFile {
			return LocationInfo(
				type: .separateFileGood,
				icon: .emoji("✅"),
				fileName: fileName,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				sizeIndicator: sizeIndicator,
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
				sizeIndicator: sizeIndicator,
				warningText: "too small for separate file"
			)
		} else {
			return LocationInfo(
				type: .separateFileNameMismatch,
				icon: .emoji("🛑"),
				fileName: fileName,
				relativePath: relativePath,
				line: line,
				endLine: endLine,
				sizeIndicator: sizeIndicator,
				warningText: nil
			)
		}
	}

	nonisolated private func children(of declaration: Declaration) -> [Declaration] {
		Array(declaration.declarations)
	}
}

private extension Declaration {
	nonisolated var firstNameComponent: String {
		name?.components(separatedBy: ".").first ?? ""
	}
}

private extension Declaration {

	nonisolated var locSize: String {
		let blackSquares = ["⬛", "◼", "▪", "·"]
		let sizeIndicator: String
		let lineSpan = (self.location.endLine ?? 0) - self.location.line
		if lineSpan > 100 {
			sizeIndicator = " " + blackSquares[0]
		} else if lineSpan > 75 {
			sizeIndicator = " " + blackSquares[1]
		} else if lineSpan > 50 {
			sizeIndicator = " " + blackSquares[2]
		} else if lineSpan > 25 {
			sizeIndicator = " " + blackSquares[3]
		} else {
			sizeIndicator = ""
		}
		return sizeIndicator
	}

	nonisolated func locString(includeFilename: Bool = true) -> String {
		let fileComponent = self.location.file.path.lastComponent ?? "nil"
		let file: String = "\(fileComponent)"
		let line = self.location.line
		let endLine: String = self.location.endLine.map { ":\($0)" } ?? ""

		return "\(includeFilename ? file : ""):\(line)\(endLine)"
	}

	/// Returns a debug string with info (kind name [file:line])
	nonisolated var debugString: String {
		let name = self.name ?? ""
		let kind = self.kind.icon
		return "\(kind) \(name) \(self.locString())\(self.locSize)"
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

