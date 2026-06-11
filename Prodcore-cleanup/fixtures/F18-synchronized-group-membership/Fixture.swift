// F18 regression repro — synchronized-folder `membershipExceptions` file must be SHELLED, not DELETED.
//
// Shape: a file that lives in an Xcode *synchronized* (blue) folder group
// (`PBXFileSystemSynchronizedRootGroup`) but is pinned individually in project.pbxproj via a
// `PBXFileSystemSynchronizedBuildFileExceptionSet`'s `membershipExceptions` list (see
// project.pbxproj.snippet in this folder). Such a file is named explicitly by the project, so Xcode
// requires it on disk — deleting it breaks the build with "Build input files cannot be found".
//
// This file is entirely dead (nothing references `OnlyDeadThingHere`), so `forceRemoveAll` removes
// every declaration. The CORRECT outcome is that Treeswift leaves an import-only SHELL on disk
// (because `XcodeProjectFileChecker.isSafeToDelete` returns false for membershipExceptions files),
// NOT that it deletes the file.
//
// Real-world origin: Prodcore baseline R-May `96e372e4` —
// Shared/CoreData/Products/ProductType.swift (+ DocumentOperations, IconReference, RegionHelpers).
//
// Expected after `forceRemoveAll`:
//   - the file STILL EXISTS on disk (reduced to an import-only shell), and
//   - the project builds (no "Build input files cannot be found").
//
// Bug behavior (pre-F18): the whole file was deleted → build failed.
//
// In-repo verification: end-to-end (the experiment's build_errors == 0 on R-May after F18).
// Unit-level: `XcodeProjectFileChecker.isSafeToDelete(filePath: ".../ProductType.swift",
//   xcodeprojPath: <proj with the snippet>)` must return `false`.

import Foundation

struct OnlyDeadThingHere {
	let unused: Int
}
