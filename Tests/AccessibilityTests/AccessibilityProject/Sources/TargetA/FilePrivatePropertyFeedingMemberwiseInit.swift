import Foundation

// A fileprivate struct with NO explicit initializer relies on the synthesized memberwise init, whose
// access is the most restrictive of its stored properties. `density` is only accessed directly within
// its own type, so it LOOKS redundantly fileprivate — but narrowing it to `private` would drop the
// synthesized memberwise init to `private`, breaking the `FPMemberwiseRows(...)` construction below
// (a different type in the same file). So `density` must NOT be flagged redundant-fileprivate.
fileprivate struct FPMemberwiseRows {
    fileprivate let density: Int
    let label: String
}

fileprivate struct FPMemberwiseUser {
    func make() -> FPMemberwiseRows {
        FPMemberwiseRows(density: 1, label: "x")
    }
}
