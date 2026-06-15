import ArgumentParser
import Foundation

public struct PeripheryCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "periphery",
        subcommands: [
            ScanCommand.self,
            CheckUpdateCommand.self,
            ClearCacheCommand.self,
            VersionCommand.self,
        ]
    )

    public init() {}
}

/// Entry point used by the thin `periphery` executable. Exposed so that the
/// command-line interface can be driven from the FrontendLib library product.
public func runPeripheryCommandLine() {
    do {
        var command = try PeripheryCommand.parseAsRoot()
        try command.run()
    } catch {
        PeripheryCommand.exit(withError: error)
    }
}
