import Foundation

// A class with a stored property that has no default value, and a single explicit
// initializer that assigns it. The class itself is retained (referenced as the type
// of a retained property below), but its sole init has no external callers.
public class FixtureClass400 {
    private var value: Int

    init(value: Int) {
        self.value = value
    }
}

public class FixtureClass400Retainer {
    public var page: FixtureClass400?
}
