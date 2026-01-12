//
//  TreeRowViews.swift
//  Treeswift
//
//  Row views for folders, files, and warnings in the tree
//

import SwiftUI
import AppKit
import PeripheryKit
import SourceGraph
import SystemPackage

struct FolderRowView: View {
	let folder: FolderNode

	var body: some View {
		HStack(spacing: 4) {
			Image(nsImage: IconCache.shared.folderIcon())
				.resizable()
				.frame(width: 16, height: 16)
			Text(folder.name)
		}
	}
}

struct FileRowView: View {
	let file: FileNode
	let filterState: FilterState?
	let scanResults: [ScanResult]
	let removingFileIDs: Set<String>
	let hiddenWarningIDs: Set<String>

	private var visibleBadges: [Badge] {
	    struct CounterKey: Hashable {
	        let swiftType: SwiftType
	        let isUnused: Bool
	    }

	    // Fixed display order
	    let orderIndex: [SwiftType: Int] = [
	        .struct: 0,
	        .class: 1,
	        .enum: 2,
	        .typealias: 3,
	        .extension: 4,
	        .parameter: 5,
	        .property: 6,
	        .initializer: 7,
	        .function: 8
	    ]

	    // 1) Slice scan results to this file once
	    let fileResults = scanResults.filter { result in
	        let declaration = result.declaration
	        let location = ScanResultHelper.location(from: declaration)
	        return location.file.path.string == file.path
	    }

	    // 2) Apply filter state (if present)
	    let filteredResults: [ScanResult] = fileResults.filter { result in
	        guard let filterState = filterState else { return true }
	        let declaration = result.declaration
	        return filterState.shouldShow(result: result, declaration: declaration)
	    }

	    // 3) Filter out hidden warnings
	    let visibleResults = filteredResults.filter { result in
	        let declaration = result.declaration
	        let location = ScanResultHelper.location(from: declaration)
	        let usr = declaration.usrs.first ?? ""
	        let warningID = "\(location.file.path.string):\(usr)"
	        return !hiddenWarningIDs.contains(warningID)
	    }

	    // 4) Count by (SwiftType, isUnused)
	    var counts: [CounterKey: Int] = [:]
	    counts.reserveCapacity(visibleResults.count)

	    for result in visibleResults {
	        let declaration = result.declaration
	        let swiftType = SwiftType.from(declarationKind: declaration.kind)
	        let key = CounterKey(swiftType: swiftType, isUnused: result.annotation.isUnused)
	        counts[key, default: 0] += 1
	    }

	    // 4) Build badges in desired order (unused first for each type)
	    var badges: [Badge] = []
	    badges.reserveCapacity(counts.count)

	    for swiftType in SwiftType.allCases {
	        // Unused first
	        let unusedKey = CounterKey(swiftType: swiftType, isUnused: true)
	        if let unusedCount = counts[unusedKey], unusedCount > 0 {
	            badges.append(Badge(
	                letter: swiftType.rawValue,
	                count: unusedCount,
	                swiftType: swiftType,
	                isUnused: true
	            ))
	        }
	        // Then other
	        let otherKey = CounterKey(swiftType: swiftType, isUnused: false)
	        if let otherCount = counts[otherKey], otherCount > 0 {
	            badges.append(Badge(
	                letter: swiftType.rawValue,
	                count: otherCount,
	                swiftType: swiftType,
	                isUnused: false
	            ))
	        }
	    }

	    // 5) Stable sort by order index (cheap, small array)
	    return badges.sorted { lhs, rhs in
	        let l = orderIndex[lhs.swiftType] ?? Int.max
	        let r = orderIndex[rhs.swiftType] ?? Int.max
	        return l < r
	    }
	}

	var body: some View {
		HStack(spacing: 4) {
			// File icon
			Image(nsImage: IconCache.shared.fileIcon(forPath: file.path))
				.resizable()
				.frame(width: 16, height: 16)

			// Filename
			Text(file.name)
				.strikethrough(removingFileIDs.contains(file.id))
				.opacity(removingFileIDs.contains(file.id) ? 0.5 : 1.0)

			// Badges (filtered)
			let badges = visibleBadges
			if !badges.isEmpty {
				HStack(spacing: 4) {
					ForEach(badges) { badge in
						BadgeView(badge: badge)
					}
				}
			}
		}
	}
}

#Preview("Folder") {
	List {
		FolderRowView(folder: FolderNode(
			id: "/path/to/folder",
			name: "Sources",
			path: "/path/to/folder",
			children: []
		))
	}
}

#Preview("File with Badges") {
	List {
		FileRowView(
			file: FileNode(
				id: "/path/to/file.swift",
				name: "ContentView.swift",
				path: "/path/to/file.swift"
			),
			filterState: nil as FilterState?,
			scanResults: [],
			removingFileIDs: [],
			hiddenWarningIDs: []
		)
	}
}

