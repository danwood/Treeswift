# Folder Organization Analysis Guide

> **About This Document**
>
> This document describes folder-based encapsulation principles being applied to the Treeswift codebase. It serves as both a reference guide and an aspirational target for code organization.
>
> **Purpose:** Comprehensive guide to folder organization philosophy
> **Audience:** Developers working on Treeswift who want to understand encapsulation patterns
> **Status:** Reference and philosophical discussion

## Overview

This document describes a systematic approach to analyzing and organizing Swift codebases using folder-based encapsulation patterns. While Swift's access control (`private`, `fileprivate`, `internal`, `public`) provides visibility control, it lacks a mechanism to restrict symbols to a specific folder. This guide establishes conventions and analysis techniques to achieve folder-based organization through static analysis rather than compiler enforcement.

## The Problem

As codebases grow, file and folder organization often becomes ad-hoc and unmanageable:
- Utilities scattered across multiple locations
- Unclear which code supports which features
- No clear boundaries between components
- Difficult to understand dependencies between modules

## The Solution: Three Folder Types

Every folder containing `.swift` files should be classified as one of three types:

### 1. Shared Folders 📦

**Purpose**: Contains reusable utilities and components referenced from multiple parts of the codebase.

**Characteristics**:
- Contains symbols (classes, structs, enums, extensions, etc.) that are used throughout the codebase
- No requirement for folder name to match any symbol name
- Conventionally named with terms indicating shared purpose

**Naming Conventions**:
- `Extensions` - Extensions on primitive types (String, Array, etc.)
- `Shared` or `Common` - General shared utilities
- `Support` or `Utilities` or `Helpers` - Supporting code
- Context-specific variations: `Shared UI`, `Foundation Extensions`, `Network Utilities`

**Validation Rules**:
- ✅ Symbols should be referenced from **multiple different folders**
- ⚠️ Symbols referenced from only **one other file** should be moved to that file's folder
- ⚠️ Symbols referenced only from **files within a single folder** should be moved into that folder

**Example**:
```
Shared UI/
├─ CustomButton.swift        // Used in EditorView/, SettingsView/, etc.
├─ ColorExtensions.swift     // Used throughout codebase
└─ LayoutHelpers.swift       // Used in multiple view folders
```

### 2. Symbol Folders 🏛️

**Purpose**: Encapsulates a main symbol (like a view, controller, or service) along with all its supporting code.

**Characteristics**:
1. **Naming requirement**: Folder name matches a file name (without `.swift`) within that folder
2. **Main symbol requirement**: That file contains an `internal` declaration matching the folder name
3. **Encapsulation requirement**: All other symbols in the folder (except the main symbol) are NOT referenced from outside the folder
4. **Nesting support**: Can contain other symbol folders recursively at any depth

**Access Rules**:
- Subfolders have full access to parent or ancestor folder's `internal` symbols
- Parent folders only access the main symbol of child symbol folders (not their support code)

> See **Symbol Folders: Folderprivate Access Rules** below for complete details on access patterns.

**Example**:
```
EditorView/                          // Symbol folder
├─ EditorView.swift                  // Main symbol: struct EditorView
├─ EditorToolbar.swift               // Support (only used within EditorView/)
├─ EditorSidebar.swift               // Support (only used within EditorView/)
└─ ButtonView/                       // Nested symbol folder
    ├─ ButtonView.swift              // Main symbol: struct ButtonView
    └─ ButtonStyle.swift             // Support (only used within ButtonView/)
```

In this example:
- `EditorView.swift` can reference `ButtonView` (the main symbol)
- `EditorView.swift` should NOT reference `ButtonStyle` (support code for ButtonView)
- `ButtonView.swift` CAN reference `EditorToolbar` (parent folder's symbols)

### Symbol Folders: Folderprivate Access Rules

When a folder follows the Symbol Folder pattern (matching folder/file/symbol names), it establishes a "folderprivate" encapsulation boundary. This section formalizes the access rules for these folders.

#### What Makes a Folder "Folderprivate"?

A folder is considered "folderprivate" when it meets these criteria:

1. **Matching names**: The folder name matches a Swift file name (without `.swift`) within that folder
2. **Main symbol**: That file contains an `internal` declaration matching the folder name
3. **Encapsulation**: All other symbols in the folder are NOT referenced from outside the folder (except by descendant folders)

The `/* folderprivate */` annotation (placed before the main symbol declaration) is recommended for documentation but not required—the naming pattern itself defines the behavior.

**Example:**
```swift
// In EditorView/EditorView.swift
/* folderprivate */
struct EditorView: View {
	// This is the main symbol - the public interface for this folder
}
```

#### Access Rules by Location

The following table defines what code in different locations can access within a folderprivate folder:

| Accessor Location | Can Access Main Symbol? | Can Access Support Symbols? | Rationale |
|---|---|---|---|
| **Same folder** | ✅ Yes | ✅ Yes | Full internal access within the folder |
| **Sibling folder** | ✅ Yes | ❌ No | Siblings see only the public interface |
| **Parent folder** | ✅ Yes | ❌ No | Parents see only the public interface |
| **Child/descendant** | ✅ Yes | ✅ Yes (all ancestors) | Children integrate with parent implementation |
| **Unrelated folder** | ✅ Yes | ❌ No | Only public interface is visible |

**Key Principle:** The main symbol is the **only** part of a folderprivate folder that should be referenced from outside, with one exception: descendant folders have full access to ancestor symbols.

#### Hierarchical Access Rules

##### Upward Access (Child → Ancestors)

A folder has **full access** to ALL `internal` symbols in ALL ancestor folders (parent, grandparent, great-grandparent, etc.).

**Why:** Descendant components need to integrate deeply with their ancestor's implementation. Restricting this access would make nested folder hierarchies impractical.

**Example:**
```
SettingsView/                          // Level 1
├─ SettingsView.swift                  // Main + support symbols
├─ SettingsUtilities.swift             // Support symbol
└─ AdvancedPanel/                      // Level 2
    ├─ AdvancedPanel.swift             // Can access SettingsUtilities
    └─ ColorPicker/                    // Level 3
        └─ ColorPicker.swift           // Can access both SettingsUtilities and AdvancedPanel support symbols
```

##### Downward Access (Parent → Children)

A folder can **only access the main symbol** of its child folders. It cannot access support symbols or other internal code within child folders.

**Why:** This preserves encapsulation of the child's implementation details.

**Example:**
```
EditorView/
├─ EditorView.swift                    // Can reference ButtonView
└─ ButtonView/
    ├─ ButtonView.swift                // Main symbol - accessible to parent
    └─ ButtonStyle.swift               // Support - NOT accessible to parent
```

✅ Allowed: `EditorView.swift` references `ButtonView`
❌ Forbidden: `EditorView.swift` references `ButtonStyle`

##### Horizontal Access (Sibling ↔ Sibling)

Sibling folders (folders with the same parent) can **only access each other's main symbols**. They cannot access support symbols.

**Why:** Sibling components are independent and should only interact through public interfaces.

**Example:**
```
UI/
├─ EditorView/
│   ├─ EditorView.swift                // Main symbol
│   └─ EditorToolbar.swift             // Support symbol
└─ SettingsView/
    ├─ SettingsView.swift              // Can reference EditorView
    └─ SettingsPanel.swift             // Cannot reference EditorToolbar
```

✅ Allowed: `SettingsView.swift` references `EditorView`
❌ Forbidden: `SettingsView.swift` references `EditorToolbar`

#### Complete Example with Access Annotations

```
EditorView/                            // Folderprivate folder (Level 1)
├─ EditorView.swift
│  └─ struct EditorView                // Main symbol - accessible everywhere
├─ EditorToolbar.swift
│  └─ struct EditorToolbar             // Support - accessible only within EditorView/ and descendants
├─ EditorUtilities.swift
│  └─ struct EditorHelper              // Support - accessible only within EditorView/ and descendants
└─ ButtonView/                         // Nested folderprivate folder (Level 2)
   ├─ ButtonView.swift
   │  └─ struct ButtonView             // Main symbol - accessible to EditorView/ and elsewhere
   └─ ButtonStyle.swift
      └─ struct ButtonStyle            // Support - accessible only within ButtonView/
```

**Access Examples:**

| Source File | Target Symbol | Allowed? | Reason |
|---|---|---|---|
| `EditorView.swift` | `ButtonView` | ✅ Yes | Parent accessing child's main symbol |
| `EditorView.swift` | `ButtonStyle` | ❌ No | Parent cannot access child's support symbols |
| `ButtonView.swift` | `EditorView` | ✅ Yes | Child accessing parent's main symbol |
| `ButtonView.swift` | `EditorToolbar` | ✅ Yes | Child has full access to ancestor symbols |
| `ButtonStyle.swift` | `EditorHelper` | ✅ Yes | Descendant has full access to ancestor symbols |
| `SettingsView.swift` | `EditorView` | ✅ Yes | Unrelated folder accessing main symbol |
| `SettingsView.swift` | `EditorToolbar` | ❌ No | Unrelated folder cannot access support symbols |

#### The `/* folderprivate */` Annotation

**Purpose:**
- Documents which symbol is the public interface for the folder
- Helps static analysis tools identify the access pattern
- Makes developer intent explicit

**Placement:**
```swift
/* folderprivate */
struct EditorView: View {
	// Implementation
}
```

Place the annotation directly before the main symbol declaration, in the same position where access control keywords like `public`, `internal`, or `private` would appear.

**Not Required for Enforcement:**
The annotation is documentation, not enforcement. A folder following the naming pattern is treated as folderprivate regardless of whether the annotation is present. However, adding it is strongly recommended as a best practice.

#### Validation Checklist

To verify a folder correctly implements the folderprivate pattern:

- [ ] Folder name matches a file name (without `.swift`) in that folder
- [ ] That file contains an `internal` symbol matching the folder name
- [ ] The main symbol has the `/* folderprivate */` annotation (recommended)
- [ ] Support symbols are NOT referenced from sibling folders
- [ ] Support symbols are NOT referenced from parent folders
- [ ] The main symbol IS referenced from outside (otherwise it's unused code)
- [ ] Child folders CAN successfully access ancestor symbols

#### Common Violations and Fixes

**Violation 1: Support Symbol Leaked to Sibling**

❌ **Problem:**
```
SettingsView/SettingsHelper.swift (support symbol)
  is referenced from:
    EditorView/EditorView.swift (sibling folder)
```

✅ **Fix:** Either:
1. Move `SettingsHelper` to a shared utilities folder
2. Refactor `EditorView` to not depend on `SettingsHelper`
3. Expose needed functionality through `SettingsView` main symbol

---

**Violation 2: Parent Accessing Child's Support Symbol**

❌ **Problem:**
```swift
// In EditorView/EditorView.swift (parent)
let style = ButtonStyle.default  // Accessing child's support symbol
```

✅ **Fix:** Make `ButtonView` expose the needed functionality:
```swift
// In ButtonView/ButtonView.swift
/* folderprivate */
struct ButtonView: View {
	static let defaultStyle = ButtonStyle.default  // Exposed through main symbol
}

// In EditorView/EditorView.swift
let style = ButtonView.defaultStyle  // Accessing through main symbol
```

---

**Violation 3: Child Cannot Access Ancestor Symbol**

❌ **Problem:**
```swift
// In ButtonView/ButtonStyle.swift
let toolbar = EditorToolbar()  // Compiler error: cannot find EditorToolbar
```

✅ **Fix:** Verify:
1. The ancestor folder contains the symbol with `internal` access
2. The folder hierarchy is correct (ButtonView is actually a descendant of EditorView)
3. No typos in symbol name or import issues

### 3. Ambiguous Folders 📁

**Status**: Needs organization work.

**Characteristics**:
- Has a main symbol but some support symbols are referenced from outside (violates encapsulation)
- Lacks clear shared folder naming but contains symbols used from multiple locations
- Is a symbol folder candidate but missing the matching file/symbol name
- Otherwise doesn't clearly fit either pattern

**Common Issues**:
- Mixed responsibilities (both shared utilities AND feature-specific code)
- Incomplete encapsulation (mostly encapsulated but a few symbols leak out)
- Generic naming that doesn't indicate purpose (`Helpers`, `Misc`, `Other`)

## Reference Counting Rules

When analyzing whether a symbol belongs in a shared folder:

### Counting Method
- **Count** = number of distinct **files** (outside the defining file) that reference the symbol
- Each usage within a file counts as one reference from that file
- Multiple usages in the same file still count as just one reference

### Examples
- `SharedColor.blue` used 5 times in `EditorView.swift` → **1 reference**
- `SharedColor.blue` used in `Main.swift`, `Toolbar.swift`, `Sidebar.swift` → **3 references**

### Validation Logic

| Reference Pattern | Assessment | Action |
|------------------|------------|--------|
| 0 references | Unused code | Remove entirely (already flagged by Periphery) |
| 1 reference from one file | Coupled to single location | Move to that file's folder |
| Multiple references from files in **same folder** | Folder-specific utility | Move into that folder |
| Multiple references from **different folders** | Truly shared | ✅ Belongs in shared folder |

### Detailed Example

Given `SharedColor.blue` defined in `Shared/ColorExtensions.swift`:

**Scenario A - Correct placement**:
```
References from:
- EditorView/Main.swift
- SettingsView/Panel.swift
- AboutView/Header.swift
→ Used from 3 different folders ✅ Correctly in Shared/
```

**Scenario B - Should relocate**:
```
References from:
- EditorView/Main.swift
- EditorView/Toolbar.swift
- EditorView/Sidebar.swift
→ Only used from EditorView/ folder ⚠️ Move to EditorView/Utilities/ or EditorView/
```

**Scenario C - Should inline**:
```
References from:
- EditorView/Main.swift
→ Only used in one file ⚠️ Move into EditorView/Main.swift or nearby
```

## Root-Level Files

Files at the project root (not in any folder):

### Acceptable
- App entry points (`.swift` files with `@main` App declarations)
- Example: `TreeswiftApp.swift` containing `@main struct TreeswiftApp: App`

### Should Be Organized
- All other `.swift` files at root should be moved into appropriate folders
- Flag as ambiguous/needing organization

### Ignored
- Non-Swift files (`.md`, `.plist`, `.gitignore`, etc.) are not part of this analysis

## Benefits of This Organization

### Clarity
- Immediately understand what code is shared vs. feature-specific
- Clear boundaries reduce cognitive load when navigating codebase

### Maintainability
- Easy to find related code (all in one folder)
- Support code changes don't ripple to unrelated areas

### Refactoring Support
- Identify candidates for extraction (complex symbol folders → split into subfolders)
- Identify candidates for consolidation (simple symbol folders → merge with parent)
- Detect misplaced code (shared code with limited usage → relocate)

### Future-Proofing
- If Swift adds folder-scoped access control (e.g., `folderprivate`), code is already organized for it
- Clean structure makes it easier to extract modules or packages later

## Common Warnings and Suggestions

### Shared Folder Warnings

**"Symbol X only referenced from [one file]"**
- The symbol should be moved into that file's folder or inlined into the file itself

**"Symbols only referenced from [FolderName]/ folder"**
- List of symbols that appear shared but are only used within one folder
- Move these into that folder (e.g., into a `Utilities/` subfolder)

### Symbol Folder Warnings

**"Support symbols leaked: [SymbolA, SymbolB]"**
- Symbol folder's support code is being referenced from outside
- Options:
  1. Move leaked symbols to a shared folder
  2. Refactor external code to use only the main symbol
  3. Reclassify folder as shared if most symbols are actually shared

**"Folder is complex (N files), consider splitting"**
- Symbol folder contains many files
- Suggestion: Identify a symbol and its support files that could become a subfolder
- Example: "Consider extracting ButtonView (and 4 support files) into subfolder"

### Ambiguous Folder Warnings

**"Folder should be renamed to indicate shared purpose"**
- Contains shared code but lacks conventional naming
- Suggestion: "Rename 'Helpers' to 'Shared Helpers' or 'UI Utilities'"

**"Folder has mixed responsibilities"**
- Contains both shared utilities and feature-specific code
- Suggestion: Split into separate folders

**"Folder missing main symbol matching name"**
- Named like a symbol folder but doesn't have the matching file/symbol
- Suggestion: "Expected to find EditorView.swift with internal EditorView declaration"

## Best Practices

### When to Create a Symbol Folder
- You have a main component (view, service, model) with several supporting files
- The support code is only relevant to that component
- You want to encapsulate implementation details

### When to Create a Shared Folder
- You have utilities genuinely used across multiple features
- Code is general-purpose (extensions, helpers, reusable components)
- No single "owner" feature

### When to Split a Symbol Folder
- Folder contains too many files (hard to navigate)
- A subset of files forms a logical sub-component
- Want to improve organization without changing functionality

### When to Merge Symbol Folders
- Symbol folder is too simple (just 1-2 files)
- Support code is minimal
- Would simplify structure without losing clarity

## Recursive Nesting Example

Symbol folders can nest indefinitely:

```
SettingsView/                        // Level 1: Symbol folder
├─ SettingsView.swift                // Main symbol
├─ SettingsUtilities.swift           // Support
└─ AdvancedPanel/                    // Level 2: Nested symbol folder
    ├─ AdvancedPanel.swift           // Main symbol
    ├─ PanelHeader.swift             // Support
    └─ ColorPicker/                  // Level 3: Nested symbol folder
        ├─ ColorPicker.swift         // Main symbol
        ├─ ColorWheel.swift          // Support
        └─ HexInput.swift            // Support
```

Access rules:
- `ColorPicker.swift` can access symbols from `AdvancedPanel.swift` and `SettingsView.swift`
- `SettingsView.swift` can access `AdvancedPanel` (main symbol) but not `PanelHeader`
- `SettingsView.swift` can access `ColorPicker` (main symbol) but not `ColorWheel` or `HexInput`

## Analysis Workflow

1. **Scan codebase** to identify all folders containing `.swift` files
2. **Identify internal symbols** defined in each folder
3. **Query references** for each symbol to find where they're used
4. **Count external references** (references from files outside the folder)
5. **Classify folders**:
   - Symbol folder if: name matches file/symbol + all support code is internal-only
   - Shared folder if: conventional naming + symbols used from multiple folders
   - Ambiguous otherwise
6. **Generate warnings**:
   - Shared code with limited usage
   - Symbol folders with leaked support symbols
   - Complex folders that could be split
   - Ambiguous folders needing reorganization

## Conclusion

This folder organization system provides:
- **Clear conventions** for organizing Swift code
- **Validation rules** to verify organization quality
- **Actionable warnings** to guide improvement
- **Scalable structure** that works from small projects to large codebases

By treating folders as organizational boundaries and using static analysis to validate those boundaries, you can achieve clean, maintainable code organization even without compiler-enforced folder-scoped access control.
