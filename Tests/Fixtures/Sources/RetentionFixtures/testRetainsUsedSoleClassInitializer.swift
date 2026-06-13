import Foundation

// A class with stored state and a sole explicit initializer that IS called. This is a sanity
// check: the initializer is referenced by its caller regardless of the sole-init retention, and
// remains retained.
public class FixtureClass402 {
    private var value: Int

    init(value: Int) {
        self.value = value
    }
}

public class FixtureClass402Retainer {
    public func build() -> FixtureClass402 {
        FixtureClass402(value: 1)
    }
}
