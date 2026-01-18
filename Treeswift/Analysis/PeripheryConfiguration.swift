//
//  PeripheryConfiguration.swift
//  Treeswift
//
//  User-facing configuration model that mirrors all options from Periphery's Configuration class
//  This struct is Codable for persistence in UserDefaults
//

import Foundation

enum ProjectType: String, Codable, Sendable {
	case xcode
	case swiftPackage
}

struct PeripheryConfiguration: Identifiable, Codable, Equatable, Sendable {
	var id: UUID
	var name: String
	var projectType: ProjectType

	// MARK: - Core Project Settings

	var project: String?
	var schemes: [String]
	var outputFormat: String // "xcode", "json", "csv", "checkstyle", "codeclimate", "github-actions"

	// MARK: - Exclusion Settings

	var excludeTests: Bool
	var excludeTargets: [String]
	var indexExclude: [String]
	var reportExclude: [String]
	var reportInclude: [String]

	// MARK: - Build Settings

	var buildArguments: [String]
	var xcodeListArguments: [String]
	var skipBuild: Bool
	var skipSchemesValidation: Bool
	var cleanBuild: Bool
	var indexStorePath: [String]

	// MARK: - Retention Settings

	var retainPublic: Bool
	var retainFiles: [String]
	var retainAssignOnlyProperties: Bool
	var retainAssignOnlyPropertyTypes: [String]
	var retainObjcAccessible: Bool
	var retainObjcAnnotated: Bool
	var retainUnusedProtocolFuncParams: Bool
	var retainSwiftUIPreviews: Bool
	var retainCodableProperties: Bool
	var retainEncodableProperties: Bool

	// MARK: - Analysis Settings

	var disableRedundantPublicAnalysis: Bool
	var disableUnusedImportAnalysis: Bool

	// MARK: - External Type Settings

	var externalEncodableProtocols: [String]
	var externalCodableProtocols: [String]
	var externalTestCaseClasses: [String]

	// MARK: - Output Settings

	var isVerbose: Bool
	var shouldLogToConsole: Bool
	var isQuiet: Bool
	var isStrict: Bool
	var isRelativeResults: Bool

	// MARK: - File Path Settings

	var baseline: String?
	var writeBaseline: String?
	var writeResults: String?

	// MARK: - Advanced Settings

	var jsonPackageManifestPath: String?
	var genericProjectConfig: String?
	var bazel: Bool
	var bazelFilter: String?
	var disableUpdateCheck: Bool

	// MARK: - Initialization

	init(
		id: UUID = UUID(),
		name: String,
		projectType: ProjectType = .xcode,
		project: String? = nil,
		schemes: [String] = [],
		outputFormat: String = "xcode",
		excludeTests: Bool = false,
		excludeTargets: [String] = [],
		indexExclude: [String] = ["**/*?.build/**/*", "**/SourcePackages/checkouts/**"],
		reportExclude: [String] = [],
		reportInclude: [String] = [],
		buildArguments: [String] = [],
		xcodeListArguments: [String] = [],
		skipBuild: Bool = false,
		skipSchemesValidation: Bool = false,
		cleanBuild: Bool = false,
		indexStorePath: [String] = [],
		retainPublic: Bool = false,
		retainFiles: [String] = [],
		retainAssignOnlyProperties: Bool = false,
		retainAssignOnlyPropertyTypes: [String] = [],
		retainObjcAccessible: Bool = false,
		retainObjcAnnotated: Bool = false,
		retainUnusedProtocolFuncParams: Bool = false,
		retainSwiftUIPreviews: Bool = false,
		retainCodableProperties: Bool = false,
		retainEncodableProperties: Bool = false,
		disableRedundantPublicAnalysis: Bool = false,
		disableUnusedImportAnalysis: Bool = false,
		externalEncodableProtocols: [String] = [],
		externalCodableProtocols: [String] = [],
		externalTestCaseClasses: [String] = [],
		verbose: Bool = false,
		logToConsole: Bool = false,
		quiet: Bool = false,
		strict: Bool = false,
		relativeResults: Bool = false,
		baseline: String? = nil,
		writeBaseline: String? = nil,
		writeResults: String? = nil,
		jsonPackageManifestPath: String? = nil,
		genericProjectConfig: String? = nil,
		bazel: Bool = false,
		bazelFilter: String? = nil,
		disableUpdateCheck: Bool = false
	) {
		self.id = id
		self.name = name
		self.projectType = projectType
		self.project = project
		self.schemes = schemes
		self.outputFormat = outputFormat
		self.excludeTests = excludeTests
		self.excludeTargets = excludeTargets
		self.indexExclude = indexExclude
		self.reportExclude = reportExclude
		self.reportInclude = reportInclude
		self.buildArguments = buildArguments
		self.xcodeListArguments = xcodeListArguments
		self.skipBuild = skipBuild
		self.skipSchemesValidation = skipSchemesValidation
		self.cleanBuild = cleanBuild
		self.indexStorePath = indexStorePath
		self.retainPublic = retainPublic
		self.retainFiles = retainFiles
		self.retainAssignOnlyProperties = retainAssignOnlyProperties
		self.retainAssignOnlyPropertyTypes = retainAssignOnlyPropertyTypes
		self.retainObjcAccessible = retainObjcAccessible
		self.retainObjcAnnotated = retainObjcAnnotated
		self.retainUnusedProtocolFuncParams = retainUnusedProtocolFuncParams
		self.retainSwiftUIPreviews = retainSwiftUIPreviews
		self.retainCodableProperties = retainCodableProperties
		self.retainEncodableProperties = retainEncodableProperties
		self.disableRedundantPublicAnalysis = disableRedundantPublicAnalysis
		self.disableUnusedImportAnalysis = disableUnusedImportAnalysis
		self.externalEncodableProtocols = externalEncodableProtocols
		self.externalCodableProtocols = externalCodableProtocols
		self.externalTestCaseClasses = externalTestCaseClasses
		isVerbose = verbose
		shouldLogToConsole = logToConsole
		isQuiet = quiet
		isStrict = strict
		isRelativeResults = relativeResults
		self.baseline = baseline
		self.writeBaseline = writeBaseline
		self.writeResults = writeResults
		self.jsonPackageManifestPath = jsonPackageManifestPath
		self.genericProjectConfig = genericProjectConfig
		self.bazel = bazel
		self.bazelFilter = bazelFilter
		self.disableUpdateCheck = disableUpdateCheck
	}

	// MARK: - Computed Properties

	/// Returns the directory path for the project
	/// For Xcode projects, returns the project path itself
	/// For Swift Package projects, returns the directory containing Package.swift
	var projectDirectory: String? {
		guard let project else { return nil }

		switch projectType {
		case .xcode:
			return project
		case .swiftPackage:
			return URL(fileURLWithPath: project).deletingLastPathComponent().path
		}
	}

	// MARK: - Migration Support

	private enum CodingKeys: String, CodingKey {
		case id
		case name
		case projectType
		case project
		case schemes
		case outputFormat
		case excludeTests
		case excludeTargets
		case indexExclude
		case reportExclude
		case reportInclude
		case buildArguments
		case xcodeListArguments
		case skipBuild
		case skipSchemesValidation
		case cleanBuild
		case indexStorePath
		case retainPublic
		case retainFiles
		case retainAssignOnlyProperties
		case retainAssignOnlyPropertyTypes
		case retainObjcAccessible
		case retainObjcAnnotated
		case retainUnusedProtocolFuncParams
		case retainSwiftUIPreviews
		case retainCodableProperties
		case retainEncodableProperties
		case disableRedundantPublicAnalysis
		case disableUnusedImportAnalysis
		case externalEncodableProtocols
		case externalCodableProtocols
		case externalTestCaseClasses
		case isVerbose
		case shouldLogToConsole
		case isQuiet
		case isStrict
		case isRelativeResults
		case baseline
		case writeBaseline
		case writeResults
		case jsonPackageManifestPath
		case genericProjectConfig
		case bazel
		case bazelFilter
		case disableUpdateCheck
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		id = try container.decode(UUID.self, forKey: .id)
		name = try container.decode(String.self, forKey: .name)

		// Migration: default to .xcode if not present
		projectType = try container.decodeIfPresent(ProjectType.self, forKey: .projectType) ?? .xcode

		project = try container.decodeIfPresent(String.self, forKey: .project)
		schemes = try container.decode([String].self, forKey: .schemes)
		outputFormat = try container.decode(String.self, forKey: .outputFormat)
		excludeTests = try container.decode(Bool.self, forKey: .excludeTests)
		excludeTargets = try container.decode([String].self, forKey: .excludeTargets)
		indexExclude = try container.decode([String].self, forKey: .indexExclude)
		reportExclude = try container.decode([String].self, forKey: .reportExclude)
		reportInclude = try container.decode([String].self, forKey: .reportInclude)
		buildArguments = try container.decode([String].self, forKey: .buildArguments)
		xcodeListArguments = try container.decode([String].self, forKey: .xcodeListArguments)
		skipBuild = try container.decode(Bool.self, forKey: .skipBuild)
		skipSchemesValidation = try container.decode(Bool.self, forKey: .skipSchemesValidation)
		cleanBuild = try container.decode(Bool.self, forKey: .cleanBuild)
		indexStorePath = try container.decode([String].self, forKey: .indexStorePath)
		retainPublic = try container.decode(Bool.self, forKey: .retainPublic)
		retainFiles = try container.decode([String].self, forKey: .retainFiles)
		retainAssignOnlyProperties = try container.decode(Bool.self, forKey: .retainAssignOnlyProperties)
		retainAssignOnlyPropertyTypes = try container.decode([String].self, forKey: .retainAssignOnlyPropertyTypes)
		retainObjcAccessible = try container.decode(Bool.self, forKey: .retainObjcAccessible)
		retainObjcAnnotated = try container.decode(Bool.self, forKey: .retainObjcAnnotated)
		retainUnusedProtocolFuncParams = try container.decode(Bool.self, forKey: .retainUnusedProtocolFuncParams)
		retainSwiftUIPreviews = try container.decode(Bool.self, forKey: .retainSwiftUIPreviews)
		retainCodableProperties = try container.decode(Bool.self, forKey: .retainCodableProperties)
		retainEncodableProperties = try container.decode(Bool.self, forKey: .retainEncodableProperties)
		disableRedundantPublicAnalysis = try container.decode(Bool.self, forKey: .disableRedundantPublicAnalysis)
		disableUnusedImportAnalysis = try container.decode(Bool.self, forKey: .disableUnusedImportAnalysis)
		externalEncodableProtocols = try container.decode([String].self, forKey: .externalEncodableProtocols)
		externalCodableProtocols = try container.decode([String].self, forKey: .externalCodableProtocols)
		externalTestCaseClasses = try container.decode([String].self, forKey: .externalTestCaseClasses)
		isVerbose = try container.decode(Bool.self, forKey: .isVerbose)
		shouldLogToConsole = try container.decode(Bool.self, forKey: .shouldLogToConsole)
		isQuiet = try container.decode(Bool.self, forKey: .isQuiet)
		isStrict = try container.decode(Bool.self, forKey: .isStrict)
		isRelativeResults = try container.decode(Bool.self, forKey: .isRelativeResults)
		baseline = try container.decodeIfPresent(String.self, forKey: .baseline)
		writeBaseline = try container.decodeIfPresent(String.self, forKey: .writeBaseline)
		writeResults = try container.decodeIfPresent(String.self, forKey: .writeResults)
		jsonPackageManifestPath = try container.decodeIfPresent(String.self, forKey: .jsonPackageManifestPath)
		genericProjectConfig = try container.decodeIfPresent(String.self, forKey: .genericProjectConfig)
		bazel = try container.decode(Bool.self, forKey: .bazel)
		bazelFilter = try container.decodeIfPresent(String.self, forKey: .bazelFilter)
		disableUpdateCheck = try container.decode(Bool.self, forKey: .disableUpdateCheck)
	}

	// MARK: - Convenience Initializers

	/// Create a demo configuration for testing
	static func demo() -> PeripheryConfiguration {
		PeripheryConfiguration(
			name: "liveshowhub",
			project: "/Users/dwood/code/SWIFTUI/liveshowhub/liveshowhub.xcodeproj",
			schemes: ["liveshowhub"],
			excludeTests: true,
			buildArguments: ["-config", "Debug", "-destination", "platform=macOS,arch=arm64"]
		)
	}
}
