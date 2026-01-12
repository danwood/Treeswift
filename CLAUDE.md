# CLAUDE.md

Project-specific guidance for Claude Code when working with Treeswift.

## What This Project Is

Treeswift is a macOS SwiftUI GUI for the Periphery static analysis tool. It uses a **local modified Periphery package** at `PeripherySource/periphery/` (managed as git subtree, tracking upstream with local modifications).

**Read [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) for:** architecture details, file organization, dependencies, technical environment, Swift version, and git subtree workflow.

## Build Command

```bash
xcodebuild -project Treeswift.xcodeproj -scheme Treeswift build
```

## Command-Line Testing Tools

Treeswift supports command-line operation for testing and automation. The built app can be invoked from the terminal:

**Finding the built executable:**

After building, locate the executable with:
```bash
find ~/Library/Developer/Xcode/DerivedData -name "Treeswift.app" -type d 2>/dev/null | head -1
```

The executable is at: `<path-to-app>/Contents/MacOS/Treeswift`

**Available commands:**

1. **List configurations:**
   ```bash
   Treeswift --list
   ```
   Prints all saved configuration names to stdout, one per line, then exits.

2. **Run a scan:**
   ```bash
   Treeswift --scan <configuration_name>
   ```
   Executes a scan for the named configuration, outputs progress and results to stderr, then exits.
   - Exit code 0: Success
   - Exit code 1: Error (config not found, scan failed, invalid arguments)

3. **Launch GUI (default):**
   ```bash
   Treeswift
   ```
   Opens the normal GUI application.

**Use these CLI tools when you need to:**
- Test scan functionality without GUI interaction
- Examine console output directly in the terminal
- Verify configuration changes
- Debug scan progress or results
- Automate testing workflows

**Note:** CLI invocations are independent processes. You can run CLI commands even while the GUI is open.

## Code Formatting

**Use .editorconfig** - Always check the project's `.editorconfig` file for indentation settings. For this project:
- Swift files: Use **tabs** (not spaces) for indentation
- Markdown: Use spaces (2)
- JSON/YAML: Use spaces (2)

## Key Project Constraints

### UI Layout
Configuration forms must follow [macOS layout guidelines](https://marioaguzman.github.io/design/layoutguidelines/):
- Right-aligned labels, left-aligned controls
- 20pt window margins, 6-12pt control spacing

### Utilities Location
Shared helper functions belong in `Utilities/` folder, not scattered across views (e.g., `DeclarationIconHelper.swift`, `TypeLabelFormatter.swift`)

## Modifying PeripherySource/periphery Files

**Goal:** Minimize diff with upstream to ease future updates.

**Rule:** Preserve original lines byte-for-byte. Make additions appear as pure insertions (+ lines), not modifications (+/- lines).

### Diff Minimization Patterns

**Adding to start of line** - split across lines:
```swift
// Bad: public final class Project {
// Good:
public
final class Project {
```

**Adding to end of line** - use leading comma on new line:
```swift
// Bad: logger: Logger, progressDelegate: ScanProgressDelegate? = nil
// Good:
logger: Logger
, progressDelegate: ScanProgressDelegate? = nil
```

**Adding to boolean expressions** - continue on new line:
```swift
// Good:
lhs.file == rhs.file && lhs.line == rhs.line && lhs.column == rhs.column
&& lhs.endLine == rhs.endLine && lhs.endColumn == rhs.endColumn
```

**Verify changes:** `git diff a2fad16 HEAD -- PeripherySource/periphery/` should show minimal modifications.

**Document all changes** in [PeripherySource/periphery/README_Treeswift.md](PeripherySource/periphery/README_Treeswift.md)
