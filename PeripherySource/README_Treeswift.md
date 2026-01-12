# Treeswift Modifications to Periphery

This document details all modifications made to the [Periphery](https://github.com/peripheryapp/periphery) package to enable deep integration with the Treeswift GUI application.

## Overview

This directory contains a modified version of the Periphery static analysis tool, managed as a **git subtree** tracking the upstream repository. The modifications expose internal modules as library products and enhance data structures to enable Treeswift to directly use Periphery's scanning infrastructure.

**Upstream Repository:** https://github.com/peripheryapp/periphery
**Base Version:** 3.2.0
**License:** MIT License

## Git Subtree Management

This package is managed as a git subtree, allowing us to:
- Track upstream changes and easily update to new Periphery versions
- Preserve local modifications in git history
- Merge upstream updates while maintaining our changes

### Update Commands

```bash
# Update to a specific version tag
git subtree pull --prefix=PeripherySource/periphery periphery-upstream 3.3.0 --squash

# Update to latest development (master branch)
git subtree pull --prefix=PeripherySource/periphery periphery-upstream master --squash

# After update, verify local modifications and re-apply if needed
git add PeripherySource/periphery/
git commit -m "Re-apply local modifications after periphery update"
```

### Viewing Modifications

The git subtree is tracked in the repository. After the initial subtree merge, upstream Periphery updates were pulled in at commit `a2fad16`. To see ONLY the local modifications made for Treeswift (excluding upstream changes), navigate to the Treeswift directory and then use these commands:

```bash
# View all local modifications to the Periphery subtree
# You can insert --name-only or --stat for variations.
git diff a2fad16 HEAD -- PeripherySource/periphery/

# Generate a patch file with all local modifications
git diff a2fad16 HEAD -- PeripherySource/periphery/ > periphery_modifications.patch
```

**Note:** Commit `a2fad16` represents the state after pulling upstream Periphery updates but before applying local modifications. This ensures the diff shows only changes made for Treeswift integration, not upstream Periphery development.

## Modified Files

```
PeripherySource/periphery/
│
├── Package.swift                                      [MAJOR MODIFICATIONS]
│   └─ Added 10 library products (Configuration, SourceGraph, FrontendLib, etc.)
│   └─ Split Frontend executable into Frontend + FrontendLib
│
└── Sources/
    │
    ├── Frontend/
    │   ├── Project.swift                              [ACCESS CONTROL + ENHANCEMENTS]
    │   │   └─ Made class public
    │   │   └─ Made init and kind property public
    │   │   └─ Added progressDelegate support
    │   │
    │   └── Scan.swift                                 [ACCESS CONTROL + API CHANGES]
    │       └─ Made class public
    │       └─ Made init and perform() public
    │       └─ Changed perform() to return (ScanResult, SourceGraph) tuple
    │       └─ Added progressDelegate support
    │
    ├── SourceGraph/Elements/
    │   ├── Location.swift                             [DATA STRUCTURE ENHANCEMENT]
    │   │   └─ Added endLine: Int? property
    │   │   └─ Added endColumn: Int? property
    │   │   └─ Updated init to accept endLine/endColumn parameters
    │   │   └─ Modified hash calculation to include end positions
    │   │   └─ Updated equality comparison for end positions
    │   │   └─ Updated relativeTo() to preserve end positions
    │   │   └─ Modified buildDescription() to include end positions
    │   │
    │   └── Declaration.swift                          [MINOR ENHANCEMENTS]
    │       └─ Minor adjustments for compatibility
    │
    ├── Indexer/
    │   └── SwiftIndexer.swift                         [FEATURE ENHANCEMENT]
    │       └─ Modified to capture and populate Location end positions
    │       └─ ~20 lines of changes for end position extraction
    │
    ├── SyntaxAnalysis/
    │   ├── DeclarationSyntaxVisitor.swift             [FEATURE ENHANCEMENT]
    │   │   └─ Extract end positions from Swift syntax nodes
    │   │   └─ ~25 lines of changes for syntax position tracking
    │   │
    │   └── SourceLocationBuilder.swift                [FEATURE ENHANCEMENT]
    │       └─ Calculate end line and column from syntax
    │       └─ ~10 lines of changes for position calculations
    │
    ├── PeripheryKit/
    │   ├── ScanResult.swift                           [ACCESS CONTROL]
    │   │   └─ Made Annotation enum public
    │   │   └─ Made declaration property public
    │   │   └─ Made annotation property public
    │   │
    │   └── Results/
    │       └── OutputFormatter.swift                  [MINOR TWEAKS]
    │           └─ Minor formatting adjustments
    │
    ├── ProjectDrivers/
    │   └── XcodeProjectDriver.swift                   [MINOR ADJUSTMENTS]
    │       └─ Minor compatibility adjustments
    │
    └── XcodeSupport/
        └── Xcodebuild.swift                           [MINOR FIXES]
            └─ Minor compatibility fixes
```

## Detailed Change Descriptions

### 1. Package.swift - Swift Package Configuration

**Purpose:** Expose internal modules as library products for external package integration

**Changes:**
- **Header Documentation:** Added comment block explaining this is a modified version for Treeswift
- **Frontend Target Split:**
  - Split original `Frontend` executable into two targets:
    - `Frontend` (executable) - Contains only `main.swift` entry point
    - `FrontendLib` (library) - Contains all other Frontend code (Project, Scan classes)
  - Allows external packages to import Frontend functionality without the executable
- **Library Products:** Exposed 10 additional library products (originally only `periphery` executable and `PeripheryKit` library):
  1. `Configuration` - Scan configuration management
  2. `SourceGraph` - Code graph representation and analysis
  3. `Shared` - Common utilities and infrastructure (Shell, SwiftVersion, etc.)
  4. `Logger` - Logging infrastructure
  5. `Extensions` - Swift standard library extensions (FilePath, String, etc.)
  6. `Indexer` - Swift index parsing and analysis
  7. `ProjectDrivers` - Project type detection and drivers (Xcode, SPM, Bazel)
  8. `SyntaxAnalysis` - SwiftSyntax-based code analysis
  9. `XcodeSupport` - Xcode project/workspace parsing (macOS only)
  10. `FrontendLib` - CLI functionality as library (Project, Scan orchestration)

**Impact:** Enables Treeswift to import and use Periphery's internal modules directly

---

### 2. Sources/Frontend/Project.swift

**Purpose:** Project detection and setup orchestration

**Changes:**
- Changed `final class Project` → `public final class Project`
- Changed `let kind: ProjectKind` → `public let kind: ProjectKind`
- Changed `convenience init(...)` → `public convenience init(...)`
- Added `progressDelegate: ScanProgressDelegate?` parameter to init
- Added progress reporting for inspection phase

**Impact:** Allows external packages to instantiate and use Project class for project setup

---

### 3. Sources/Frontend/Scan.swift

**Purpose:** Scan orchestration and execution

**Changes:**
- Changed `final class Scan` → `public final class Scan`
- Changed `required init(...)` → `public required init(...)`
- Changed `func perform(...)` → `public func perform(...)`
- Modified return type: `[ScanResult]` → `([ScanResult], SourceGraph)`
- Added `progressDelegate: ScanProgressDelegate?` parameter to init
- Added progress reporting throughout scan phases
- Now returns both scan results and the complete source graph

**Impact:** Enables external packages to run scans and access both results and the analyzed code graph

---

### 4. Sources/SourceGraph/Elements/Location.swift

**Purpose:** Represent source code locations for declarations

**Changes:**
- Added `public let endLine: Int?` property
- Added `public let endColumn: Int?` property
- Updated `init(file:line:column:)` to `init(file:line:column:endLine:endColumn:)`
  - `endLine` and `endColumn` are optional parameters (default: nil)
- Modified hash calculation to include `endLine` and `endColumn`
- Updated `==` operator to compare end positions
- Modified `relativeTo(_:)` to preserve end positions
- Updated `buildDescription(path:)` to include end positions in output format
  - Format: `path:line:column:endLine:endColumn` (when end positions available)

**Impact:** Enables tracking full source ranges for declarations, not just start positions

---

### 4a. Sources/SourceGraph/Elements/Location.swift - Swift 6 Concurrency

**Purpose:** Make Location thread-safe for Swift 6 strict concurrency

**Changes:**
- Added `: @unchecked Sendable` conformance to Location class
  - Used line-separated format to minimize diff (following CLAUDE.md guidelines):
    ```swift
    public class Location
    : @unchecked Sendable {
    ```
- Justification: Location instances are immutable after creation; all properties are `let` constants
- Enables safe concurrent access to Location objects without MainActor isolation

**Impact:** Eliminates Swift 6 concurrency warnings when accessing Location from nonisolated contexts

---

### 5. Sources/SourceGraph/Elements/Declaration.swift

**Purpose:** Declaration representation in source graph

**Changes:**
- Minor compatibility adjustments for end position tracking
- Changes to support enhanced Location structure
- **Swift 6 Concurrency:** Added `: @unchecked Sendable` conformance
  - Used line-separated format to minimize diff (following CLAUDE.md guidelines):
    ```swift
    public final class Declaration
    : @unchecked Sendable {
    ```
  - Justification: Declaration instances are immutable after graph construction
  - Enables safe concurrent access without MainActor isolation

**Impact:** Minimal - supports Location enhancements and Swift 6 concurrency compliance

---

### 6. Sources/Indexer/SwiftIndexer.swift

**Purpose:** Index Swift source files and populate source graph

**Changes:**
- Modified to capture end positions from index store
- Populate Location objects with endLine and endColumn data
- Approximately 20 lines of changes for end position extraction

**Impact:** Ensures Location objects are populated with complete range information during indexing

---

### 7. Sources/SyntaxAnalysis/DeclarationSyntaxVisitor.swift

**Purpose:** Visit Swift syntax nodes to extract declaration information

**Changes:**
- Extract end positions from Swift syntax nodes
- Pass end position information to Location creation
- Approximately 25 lines of changes for end position tracking
- Updated visitor methods to capture syntax node end positions

**Impact:** Ensures syntax analysis phase captures full declaration ranges

---

### 8. Sources/SyntaxAnalysis/SourceLocationBuilder.swift

**Purpose:** Build Location objects from Swift syntax

**Changes:**
- Calculate end line and column from syntax nodes
- Extract end position using `syntax.endLocation` or equivalent
- Approximately 10 lines of changes for position calculation
- New helper methods for end position extraction

**Impact:** Provides infrastructure for creating Locations with complete range data

---

### 9. Sources/PeripheryKit/ScanResult.swift

**Purpose:** Represent scan results with declarations and annotations

**Changes:**
- Changed `enum Annotation` → `public enum Annotation`
- Changed `let declaration: Declaration` → `public let declaration: Declaration`
- Changed `let annotation: Annotation` → `public let annotation: Annotation`
- Used line-separated format to minimize diff impact (following CLAUDE.md guidelines)

**Impact:** Enables external packages to inspect scan result annotations (unused, redundantPublicAccessibility, etc.) and access declaration details

---

### 10. Sources/PeripheryKit/Results/OutputFormatter.swift

**Purpose:** Format scan results for output

**Changes:**
- Minor formatting adjustments
- Potential use of end position data in output formatting

**Impact:** Minimal - formatting consistency

---

### 11. Sources/ProjectDrivers/XcodeProjectDriver.swift

**Purpose:** Drive Xcode project analysis

**Changes:**
- Minor compatibility adjustments
- Support for enhanced project scanning

**Impact:** Minimal - compatibility

---

### 12. Sources/XcodeSupport/Xcodebuild.swift

**Purpose:** Interface with xcodebuild tool

**Changes:**
- Minor fixes for compatibility
- Bug fixes or adjustments for Xcode integration

**Impact:** Minimal - stability improvements

---

## Summary Statistics

**Total Files Modified:** 12 files
**Estimated Changes:** ~954 insertions, ~32 deletions (includes Swift 6 concurrency conformances)

**Categories:**
- **Major Changes (Package Configuration):** 1 file (Package.swift)
- **Access Control Changes (Public APIs):** 3 files (Project.swift, Scan.swift, ScanResult.swift)
- **Data Structure Enhancements:** 4 files (Location.swift, SwiftIndexer.swift, DeclarationSyntaxVisitor.swift, SourceLocationBuilder.swift)
- **Swift 6 Concurrency:** 2 files (Location.swift, Declaration.swift - added @unchecked Sendable)
- **Minor Adjustments:** 4 files (Declaration.swift, OutputFormatter.swift, XcodeProjectDriver.swift, Xcodebuild.swift)

## Modification Philosophy

All changes follow these principles:

1. **Minimal Invasiveness:** Changes are limited to what's necessary for Treeswift integration
2. **Backward Compatible:** Original Periphery functionality remains unchanged
3. **Well-Documented:** All modifications are documented with comments (especially in Package.swift)
4. **Merge-Friendly:** Changes are designed to minimize merge conflicts when updating from upstream
5. **Additive:** New features (like end position tracking) are additions, not replacements

## Integration with Treeswift

These modifications enable Treeswift to:

- **Import internal modules** - Access Configuration, SourceGraph, FrontendLib, etc.
- **Instantiate scan infrastructure** - Create Project and Scan instances programmatically
- **Run scans directly** - Execute Periphery scans without shell commands
- **Access scan results** - Retrieve both ScanResult arrays and the complete SourceGraph
- **Track declaration ranges** - Use full source ranges (start + end positions) for declarations
- **Implement custom analysis** - Build on Periphery's infrastructure for GUI-specific features

## Maintenance Notes

When updating to new Periphery versions:

1. **Pull upstream changes** using git subtree commands (see above)
2. **Review merge conflicts** - Focus on the 12 modified files listed in this document
3. **Re-apply modifications** if any were overwritten:
   - Package.swift changes (library products, Frontend split)
   - Public modifiers on Project, Scan, and ScanResult classes
   - Location endLine/endColumn additions
   - ScanResult public annotation access
   - Other enhancements as documented above
4. **Test thoroughly** - Ensure Treeswift still builds and scans work correctly
5. **Update this document** if new modifications are made

## Questions or Issues

If you encounter issues with these modifications or need to make additional changes, refer to:
- Main project documentation: [CLAUDE.md](../../CLAUDE.md)
- Implementation notes: [IMPLEMENTATION_NOTES.md](../../IMPLEMENTATION_NOTES.md)
- Upstream Periphery: https://github.com/peripheryapp/periphery

---

*Last Updated: 2025-10-24*
*Periphery Base Version: 3.2.0*
*Modifications maintained by: Treeswift project*
