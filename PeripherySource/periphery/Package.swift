// swift-tools-version:6.0
import PackageDescription

// 🌲 MODIFIED VERSION FOR LOCAL PACKAGE USAGE
// This Package.swift has been modified from the upstream Periphery package to enable
// deep integration with Treeswift. All changes expose internal modules as library
// products so they can be imported by external packages.

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-system", from: "1.0.0"),
    .package(url: "https://github.com/jpsim/Yams", from: "6.0.0"),
    .package(url: "https://github.com/tadija/AEXML", from: "4.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    .package(url: "https://github.com/kateinoigakukun/swift-indexstore", from: "0.4.0"),
    .package(url: "https://github.com/apple/swift-syntax", from: "601.0.1"),
    .package(url: "https://github.com/ileitch/swift-filename-matcher", from: "2.0.0"),
]

#if os(macOS)
    dependencies.append(
        .package(
            url: "https://github.com/tuist/xcodeproj",
            from: "9.0.0"
        )
    )
#endif

var projectDriverDependencies: [PackageDescription.Target.Dependency] = [
    .target(name: "SourceGraph"),
    .target(name: "Shared"),
    .target(name: "Indexer"),
]

#if os(macOS)
    projectDriverDependencies.append(.target(name: "XcodeSupport"))
#endif

var targets: [PackageDescription.Target] = [
    // 🌲 MODIFICATION: Split Frontend into executable + library
    // Original: Single executableTarget with all Frontend code
    // Modified: Separated to allow FrontendLib to be imported by external packages
    .executableTarget(
        name: "Frontend",
        dependencies: [
            .target(name: "FrontendLib"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        path: "Sources/Frontend",
        sources: ["main.swift"]
    ),
    .target(
        name: "FrontendLib",
        dependencies: [
            .target(name: "Shared"),
            .target(name: "Configuration"),
            .target(name: "SourceGraph"),
            .target(name: "PeripheryKit"),
            .target(name: "ProjectDrivers"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
            .product(name: "FilenameMatcher", package: "swift-filename-matcher"),
        ]
        , path: "Sources/Frontend",
        exclude: ["main.swift"]
    ),
    .target(
        name: "Configuration",
        dependencies: [
            .target(name: "Extensions"),
            .target(name: "Shared"),
            .target(name: "Logger"),
            .product(name: "Yams", package: "Yams"),
            .product(name: "SystemPackage", package: "swift-system"),
            .product(name: "FilenameMatcher", package: "swift-filename-matcher"),
        ]
    ),
    .target(
        name: "Extensions",
        dependencies: [
            .product(name: "SystemPackage", package: "swift-system"),
            .product(name: "FilenameMatcher", package: "swift-filename-matcher"),
        ]
    ),
    .target(name: "Logger"),
    .target(
        name: "PeripheryKit",
        dependencies: [
            .target(name: "SourceGraph"),
            .target(name: "Shared"),
            .target(name: "Indexer"),
            .product(name: "SystemPackage", package: "swift-system"),
            .product(name: "AEXML", package: "AEXML"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftIndexStore", package: "swift-indexstore"),
            .product(name: "FilenameMatcher", package: "swift-filename-matcher"),
        ]
    ),
    .target(
        name: "Indexer",
        dependencies: [
            .target(name: "SyntaxAnalysis"),
            .target(name: "Shared"),
            .product(name: "SwiftIndexStore", package: "swift-indexstore"),
            .product(name: "AEXML", package: "AEXML"),
        ]
    ),
    .target(
        name: "ProjectDrivers",
        dependencies: projectDriverDependencies
    ),
    .target(
        name: "SyntaxAnalysis",
        dependencies: [
            .target(name: "SourceGraph"),
            .target(name: "Shared"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax"),
        ]
    ),
    .target(
        name: "SourceGraph",
        dependencies: [
            .target(name: "Configuration"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .target(name: "Shared"),
        ]
    ),
    .target(
        name: "Shared",
        dependencies: [
            .target(name: "Extensions"),
            .target(name: "Logger"),
            .product(name: "SystemPackage", package: "swift-system"),
            .product(name: "FilenameMatcher", package: "swift-filename-matcher"),
        ]
    ),
    .target(
        name: "TestShared",
        dependencies: [
            .target(name: "PeripheryKit"),
            .target(name: "ProjectDrivers"),
            .target(name: "Configuration"),
        ],
        path: "Tests/Shared"
    ),
    .testTarget(
        name: "PeripheryTests",
        dependencies: [
            .target(name: "TestShared"),
            .target(name: "PeripheryKit"),
        ]
    ),
    .testTarget(
        name: "SPMTests",
        dependencies: [
            .target(name: "TestShared"),
            .target(name: "PeripheryKit"),
        ],
        exclude: ["SPMProject"]
    ),
    .testTarget(
        name: "AccessibilityTests",
        dependencies: [
            .target(name: "TestShared"),
            .target(name: "PeripheryKit"),
            .target(name: "Configuration"),
        ],
        exclude: ["AccessibilityProject"]
    ),
]

#if os(macOS)
    targets.append(contentsOf: [
        .target(
            name: "XcodeSupport",
            dependencies: [
                .target(name: "SourceGraph"),
                .target(name: "Shared"),
                .target(name: "PeripheryKit"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .testTarget(
            name: "XcodeTests",
            dependencies: [
                .target(name: "ProjectDrivers"),
                .target(name: "TestShared"),
                .target(name: "PeripheryKit"),
            ],
            exclude: ["UIKitProject", "SwiftUIProject"]
        ),
    ])
#endif

let package = Package(
    name: "Periphery",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "periphery", targets: ["Frontend"]),
        .library(name: "PeripheryKit", targets: ["PeripheryKit"]),

		// 🌲 MODIFICATION: Additional library products exposed for external package integration
		// These internal modules are exposed to allow Treeswift and other consumers
		// to import and use Periphery's internals directly for deep integration
        .library(name: "Configuration", targets: ["Configuration"]),
        .library(name: "SourceGraph", targets: ["SourceGraph"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "Logger", targets: ["Logger"]),
        .library(name: "Extensions", targets: ["Extensions"]),
        .library(name: "Indexer", targets: ["Indexer"]),
        .library(name: "ProjectDrivers", targets: ["ProjectDrivers"]),
        .library(name: "SyntaxAnalysis", targets: ["SyntaxAnalysis"]),
        .library(name: "XcodeSupport", targets: ["XcodeSupport"]),
        .library(name: "FrontendLib", targets: ["FrontendLib"]),
    ],
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v5]
)
