import Foundation

// A struct with a sole explicit initializer that has no external callers. A struct synthesizes
// a memberwise initializer, so an unused explicit struct init is genuinely dead code. The
// class-specific retention must NOT extend to structs: this init should remain reportable as unused.
public struct FixtureStruct225 {
    private var value: Int

    init(value: Int) {
        self.value = value
    }
}
