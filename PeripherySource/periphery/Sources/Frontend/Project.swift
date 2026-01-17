import Configuration
import Foundation
import Logger
import ProjectDrivers
import Shared
import SystemPackage

public
final class Project {
    public
    let kind: ProjectKind

    private let configuration: Configuration
    private let shell: Shell
    private let logger: Logger
    private weak var progressDelegate: ScanProgressDelegate? // 🌲 Found throughout file

    public
    convenience init(
        configuration: Configuration,
        shell: Shell,
        logger: Logger
        , progressDelegate: ScanProgressDelegate? = nil
    ) throws {
        progressDelegate?.didStartInspecting()
        var kind: ProjectKind?

        if let path = configuration.project {
            kind = .xcode(projectPath: path)
        } else if let path = configuration.genericProjectConfig {
            kind = .generic(genericProjectConfig: path)
        } else if BazelProjectDriver.isSupported, configuration.bazel {
            kind = .bazel
        } else if SPM.isSupported {
            kind = .spm
        }

        guard let kind else {
            throw PeripheryError.usageError("Failed to identify project in the current directory. For Xcode projects use the '--project' option, and for SPM projects change to the directory containing the Package.swift.")
        }

        self.init(kind: kind, configuration: configuration, shell: shell, logger: logger
                  , progressDelegate: progressDelegate)
    }

    public
    init(
        kind: ProjectKind,
        configuration: Configuration,
        shell: Shell,
        logger: Logger
        , progressDelegate: ScanProgressDelegate? = nil
    ) {
        self.kind = kind
        self.configuration = configuration
        self.shell = shell
        self.logger = logger
        self.progressDelegate = progressDelegate
    }

    public
    func driver() throws -> ProjectDriver {
        switch kind {
        case let .xcode(projectPath):
            #if canImport(XcodeSupport)
                return try XcodeProjectDriver(
                    projectPath: projectPath,
                    configuration: configuration,
                    shell: shell,
                    logger: logger
                    , progressDelegate: progressDelegate
                )
            #else
                fatalError("Xcode projects are not supported on this platform.")
            #endif
        case .spm:
            return try SPMProjectDriver(configuration: configuration, shell: shell, logger: logger)
        case .bazel:
            return BazelProjectDriver(
                configuration: configuration,
                shell: shell,
                logger: logger
            )
        case let .generic(genericProjectConfig):
            return try GenericProjectDriver(
                genericProjectConfig: genericProjectConfig,
                configuration: configuration
            )
        }
    }
}
