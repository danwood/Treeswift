import Foundation

// A class with stored state but TWO explicit initializers. Neither has external callers.
// The narrow sole-init retention must NOT fire here: the user has alternatives, so both
// initializers should remain reportable as unused.
public class FixtureClass401 {
    private var value: Int

    init(value: Int) {
        self.value = value
    }

    init(other: Int) {
        value = other
    }
}
