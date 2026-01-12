import SourceGraph
import SwiftSyntax

public final class SourceLocationBuilder {
    private let file: SourceFile
    private let locationConverter: SourceLocationConverter

    public init(file: SourceFile, locationConverter: SourceLocationConverter) {
        self.file = file
        self.locationConverter = locationConverter
    }

    public func location(at position: AbsolutePosition) -> Location {
        let location = locationConverter.location(for: position)
        return Location(file: file,
                        line: location.line,
                        column: location.column)
    }
    
    public func location(from startPosition: AbsolutePosition, to endPosition: AbsolutePosition) -> Location {
        let startLocation = locationConverter.location(for: startPosition)
        let endLocation = locationConverter.location(for: endPosition)
        return Location(file: file,
                        line: startLocation.line,
                        column: startLocation.column,
                        endLine: endLocation.line,
                        endColumn: endLocation.column)
    }
}
