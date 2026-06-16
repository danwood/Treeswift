import Foundation

public struct FixtureStruct240: Identifiable, Hashable, Sendable {
    public let id: UUID
    fileprivate let startTick: TimeInterval
    private let endTick: TimeInterval
    private let aliasId: UUID?
    private let status: FixtureEnum240

    enum FixtureEnum240: Hashable, Sendable {
        case unknown
    }
}
