import Foundation

// A `let` property supplied by an explicit, used initializer is a stored value that simply isn't
// read, not an assign-only property. Removing it would orphan `self.identifier = identifier` and
// drop the initializer parameter that the call site below relies on.
public struct FixtureStruct230: Identifiable {
    public let id = UUID()
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }
}

// The initializer of this type is never called, so the `let` property remains safely removable and
// is still reported as assign-only.
public struct FixtureStruct231 {
    let identifier: String

    init(identifier: String) {
        self.identifier = identifier
    }
}

public struct FixtureStruct230Retainer {
    public func retain() {
        _ = FixtureStruct230(identifier: "")
    }
}
