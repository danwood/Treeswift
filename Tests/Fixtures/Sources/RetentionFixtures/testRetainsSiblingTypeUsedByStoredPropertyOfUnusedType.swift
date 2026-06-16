import Foundation

enum FixtureSiblingPlacement: Hashable, Sendable {
    case leading
    case trailing
}

public struct FixtureSiblingDescriptor {
    public let title: String
    let placement: FixtureSiblingPlacement
}
