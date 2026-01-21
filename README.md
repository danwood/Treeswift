# Treeswift

A modern macOS tool for analyzing and organizing your Swift codebase.

**This app is still very much in progress. No point in reporting bugs just yet; I’m still working on the basic functionality.**

**Treeswift** helps Swift developers understand their code structure, eliminate unused code, and improve encapsulation in iOS, macOS, and server-side Swift projects through an intuitive native macOS interface.

## Requirements

- macOS 15.6 "Sequoia" or higher
- Xcode (for building and for analyzing Xcode projects)

## Status

This is an early preview release. Feedback and contributions are welcome via [GitHub Issues](../../issues).

## Features

- **Native macOS Interface**
- **Multiple Configurations** - Save and manage multiple project configurations with persistent settings
- **Automatic Scheme Detection** - Detects available schemes from Xcode projects automatically
- **Multiple Result Views** - Four complementary views of your codebase:
  - **Unused Code Analysis**: Identify unused declarations and dead code
  - **Tree Tab**: Hierarchical view organized by subview structure
  - **View Extensions Tab**: SwiftUI View extensions categorized and organized
  - **Shared Tab**: Shared code elements and utilities
- **Context-Sensitive Details** - Right panel shows detailed information about selected items and controls to fix code warnings
- **Drag-and-Drop Support** - Drop project files onto the sidebar to create configurations

## User Interface

Treeswift uses a three-column layout:

### Sidebar
- List of saved project configurations (Xcode projects and Swift Packages)
- Drag-and-drop support for adding new projects
- Add (+) and Delete (−) buttons for configuration management

### Main Panel
**Configuration Section:**
- Scheme selector for Xcode projects (automatically detected)
- Build arguments and scanning options
- Layout and display preferences

**Results Section:**
- Four tabs showing different views of scan results
- Progress indicator during scanning
- Error reporting for failed scans

### Details Panel
Shows context-aware information based on the selected tab:
- **Unused Code Tab**: File/folder information, Xcode integration buttons, analysis warnings, buttons to fix or hide warnings
- **Other Tabs**: Declaration details, type information, conformances, relationships, size indicators, and referencers

## Installation

### Building from Source

Clone the repository and build using Xcode.

```bash
git clone https://github.com/danwood/treeswift.git
```


## Usage

### Quick Start

1. **Create a Configuration**
   - Drag an Xcode project (.xcodeproj) or workspace (.xcworkspace) or folder containing a Package.swift file onto the sidebar, or
   - Click the + button and select your project file

2. **Select Schemes**
   - For Xcode projects, click the schemes button to select which schemes to analyze
   - Schemes are automatically detected from your project

3. **Configure Options** (optional)
   - Add build arguments if needed
   - Adjust scanning options in the collapsible sections

4. **Run Scan**
   - Click the "Build & Scan" button in the toolbar
   - Watch the progress indicator as the scan runs

5. **Explore the Results**!

### Command-Line Interface

Treeswift supports command-line operation for automation and testing:

```bash
# List all saved configurations
Treeswift --list

# Run a scan for a specific configuration
Treeswift --scan "MyProject"

# Launch the GUI (default behavior)
Treeswift
```

The CLI is useful for:
- Testing scan functionality without GUI interaction
- CI/CD integration
- Automated testing workflows
- Debugging scan output

## Analysis Components

Treeswift integrates the [Periphery](https://github.com/peripheryapp/periphery) static analysis engine as one component of its analysis capabilities. The app includes a recent version of Periphery as a git subtree, with modifications to enable deeper integration and enhanced analysis features.

## Contributing

Contributions are welcome! Please open an issue to discuss proposed changes or submit a pull request.

## Acknowledgments

Treeswift incorporates components from [Periphery](https://github.com/peripheryapp/periphery) by Ian Leitch and contributors.
