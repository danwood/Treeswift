//
//  PeripheryConfiguration+Conversion.swift
//  Treeswift
//
//  Extension to convert PeripheryConfiguration to Periphery's Configuration class
//

import Configuration
import Foundation
import SystemPackage

/*
 SPM Project Handling - Implementation Notes
 ===========================================

 How SPM Projects Differ from Xcode Projects
 -------------------------------------------

 Xcode Projects:
 - Use schemes to define what to build and how
 - Periphery command: `periphery scan --project MyApp.xcodeproj --schemes MyApp`
 - We parse .xcodeproj to list available schemes
 - User selects which schemes to scan

 SPM Projects:
 - NO schemes concept - SPM uses Products and Targets instead
 - Periphery command: `periphery scan` (no project or scheme args)
 - Periphery auto-detects Package.swift from working directory
 - Builds ALL targets with: `swift build --build-tests`
 - No product/target selection needed for basic scanning

 Current Implementation (Lines 18-26)
 ------------------------------------
 For SPM projects, we intentionally:
 1. Do NOT set config.project (leave nil for auto-detection)
 2. Do NOT set config.schemes (schemes don't exist in SPM)
 3. Change working directory to package folder (see PeripheryScanRunner.swift:167-169)

 This is CORRECT and requires no changes to work properly.

 Future Enhancement: Display Products/Targets
 --------------------------------------------

 While not required for scanning, we could enhance the UI to show users
 what will be scanned by reading Package.swift metadata.

 Reading Package Information:

 Command:
   swift package dump-package

 Output: JSON with package structure

 Example structure:
 {
   "name": "SwiftUICharts",
   "products": [
     {
       "name": "SwiftUICharts",
       "type": { "library": ["automatic"] },
       "targets": ["SwiftUICharts"]
     }
   ],
   "targets": [
     {
       "name": "SwiftUICharts",
       "type": "library",
       "path": "Sources/SwiftUICharts"
     },
     {
       "name": "SwiftUIChartsTests",
       "type": "test",
       "path": "Tests/SwiftUIChartsTests"
     }
   ]
 }

 Key Fields:
 - products[].name: What the package produces (libraries, executables, plugins)
 - products[].type: Product type (library, executable, plugin)
 - targets[].name: Individual compilation units
 - targets[].type: Target type ("library", "test", "executable", "binary", "plugin")

 Potential UI Enhancements:

 1. Informational Display
    - Show products and targets in configuration form
    - Let users see what will be scanned
    - Display as read-only information

 2. Target Exclusion
    - Add UI for selecting targets to exclude
    - Map to existing excludeTargets configuration (line 33)
    - Similar to how excludeTests works
    - Example: Exclude test targets, executable targets, etc.

 Implementation Approach:

 1. Create SPMPackageReader utility (similar to XcodeSchemeReader):
    - Run: swift package dump-package
    - Parse JSON response
    - Cache results by package path
    - Extract products and targets

 2. Add to ConfigurationFormView:
    - Show products section (read-only, informational)
    - Show targets with checkboxes for exclusion
    - Only display when projectType == .swiftPackage

 3. Decodable models:
    struct SPMPackageDescription: Decodable {
        let name: String
        let products: [SPMProduct]
        let targets: [SPMTarget]
    }

    struct SPMProduct: Decodable {
        let name: String
        let type: SPMProductType
        let targets: [String]
    }

    struct SPMProductType: Decodable {
        let library: [String]?
        let executable: String?
        let plugin: String?
    }

    struct SPMTarget: Decodable {
        let name: String
        let type: String  // "library", "test", "executable", "binary", "plugin"
        let path: String?
    }

 4. ConfigurationFormView additions:
    // After Build Args section (line ~98)
    if configuration.projectType == .swiftPackage {
        // Products Section (Informational)
        LabeledContent {
            Text(productsDisplay)
                .foregroundStyle(.secondary)
        } label: {
            Text("Products:")
        }

        // Targets Section (For exclusion)
        LabeledContent {
            TargetSelectionPopover(
                availableTargets: availableTargets,
                excludedTargets: $configuration.excludeTargets
            )
        } label: {
            Text("Targets:")
        }
    }

 Notes:
 - Test targets can already be excluded via excludeTests flag (line 32)
 - Additional target exclusion via excludeTargets is optional
 - Most users won't need target selection - scanning everything is typical
 - This enhancement is purely for advanced users who want fine control

 References:
 - SPM.swift (PeripherySource/periphery/Sources/ProjectDrivers/SPM.swift)
   - Shows how Periphery reads package info (line 41-61)
   - Uses same `swift package describe --type json` command
 - SPMProjectDriver.swift (PeripherySource/periphery/Sources/ProjectDrivers/SPMProjectDriver.swift)
   - Shows that --schemes throws error for SPM (line 15-16)
   - Uses testTargetNames() to filter tests (line 53)
 */

extension PeripheryConfiguration {
	/// Convert this PeripheryConfiguration to Periphery's Configuration object
	func toConfiguration() -> Configuration {
		let config = Configuration()

		// Core Project Settings
		// For Xcode projects, set project path. For SPM, leave nil so Periphery auto-detects from working directory
		if projectType == .xcode, let project {
			config.project = FilePath(project)
		}

		// Schemes only apply to Xcode projects
		if projectType == .xcode {
			config.schemes = schemes
		}

		// Output format
		config.outputFormat = OutputFormat(rawValue: outputFormat) ?? .xcode

		// Exclusion Settings
		config.excludeTests = excludeTests
		config.excludeTargets = excludeTargets
		config.indexExclude = indexExclude
		config.reportExclude = reportExclude
		config.reportInclude = reportInclude

		// Build Settings
		config.buildArguments = buildArguments
		config.xcodeListArguments = xcodeListArguments
		config.skipBuild = skipBuild
		config.skipSchemesValidation = skipSchemesValidation
		config.cleanBuild = cleanBuild
		config.indexStorePath = indexStorePath.map { FilePath($0) }

		// Retention Settings
		config.retainPublic = retainPublic
		config.retainFiles = retainFiles
		config.retainAssignOnlyProperties = retainAssignOnlyProperties
		config.retainAssignOnlyPropertyTypes = retainAssignOnlyPropertyTypes
		config.retainObjcAccessible = retainObjcAccessible
		config.retainObjcAnnotated = retainObjcAnnotated
		config.retainUnusedProtocolFuncParams = retainUnusedProtocolFuncParams
		config.retainSwiftUIPreviews = retainSwiftUIPreviews
		config.retainCodableProperties = retainCodableProperties
		config.retainEncodableProperties = retainEncodableProperties

		// External Type Settings
		config.externalEncodableProtocols = externalEncodableProtocols
		config.externalCodableProtocols = externalCodableProtocols
		config.externalTestCaseClasses = externalTestCaseClasses

		// Output Settings
		config.verbose = isVerbose
		config.quiet = isQuiet
		config.strict = isStrict
		config.relativeResults = isRelativeResults

		// File Path Settings
		if let baseline {
			config.baseline = FilePath(baseline)
		}
		if let writeBaseline {
			config.writeBaseline = FilePath(writeBaseline)
		}
		if let writeResults {
			config.writeResults = FilePath(writeResults)
		}

		// Advanced Settings
		if let jsonPackageManifestPath {
			config.jsonPackageManifestPath = FilePath(jsonPackageManifestPath)
		}
		if let genericProjectConfig {
			config.genericProjectConfig = FilePath(genericProjectConfig)
		}

		return config
	}
}
