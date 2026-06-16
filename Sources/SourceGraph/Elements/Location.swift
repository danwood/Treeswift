import Foundation
import SystemPackage

public final class Location: @unchecked Sendable {
    public let file: SourceFile
    public let line: Int
    public let column: Int
    // End-position metadata. Carried for richer output but deliberately excluded
    // from equality and hashing so a location with end positions compares equal to
    // the same start position without them. This keeps location-based lookups stable
    // when end positions are applied to a declaration after indexing.
    public let endLine: Int?
    public let endColumn: Int?

    private let hashValueCache: Int

    public init(file: SourceFile, line: Int, column: Int, endLine: Int? = nil, endColumn: Int? = nil) {
        self.file = file
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
        hashValueCache = [file.hashValue, line, column].hashValue
    }

    func relativeTo(_ path: FilePath) -> Location {
        let newPath = file.path.relativeTo(path)
        let newFile = SourceFile(path: newPath, modules: file.modules)
        newFile.importStatements = file.importStatements
        return Location(file: newFile, line: line, column: column, endLine: endLine, endColumn: endColumn)
    }

    // MARK: - Private

    private func buildDescription(path: String) -> String {
        var components = [path, line.description, column.description]
        if let endLine, let endColumn {
            components.append(endLine.description)
            components.append(endColumn.description)
        }
        return components.joined(separator: ":")
    }

    private lazy var descriptionInternal: String = buildDescription(path: file.path.string)

    private lazy var shortDescriptionInternal: String = buildDescription(path: file.path.lastComponent?.string ?? "")
}

extension Location: Equatable {
    public static func == (lhs: Location, rhs: Location) -> Bool {
        lhs.file == rhs.file && lhs.line == rhs.line && lhs.column == rhs.column
    }
}

extension Location: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashValueCache)
    }
}

extension Location: CustomStringConvertible {
    public var description: String {
        descriptionInternal
    }

    public var shortDescription: String {
        shortDescriptionInternal
    }
}

extension Location: Comparable {
    public static func < (lhs: Location, rhs: Location) -> Bool {
        if lhs.file == rhs.file {
            if lhs.line == rhs.line {
                return lhs.column < rhs.column
            }

            return lhs.line < rhs.line
        }

        return lhs.file < rhs.file
    }
}
