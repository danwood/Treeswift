import Foundation

// 🌲 Regression fixture for the "custom type used only as a retained Codable property's type"
// false positive (PeripheryIssues.md #16 / README_Treeswift.md P13). When retainCodableProperties
// is enabled, FixtureStruct200's `value` property is retained — and so must its declared type
// FixtureStruct201, which is otherwise unreferenced. Without the fix, FixtureStruct201 is removed
// while `value` survives, leaving an unresolvable type annotation.

public struct FixtureStruct200: Codable {
    let value: FixtureStruct201
}

struct FixtureStruct201: Codable {
    let decimal: Decimal

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.decimal = Decimal(string: raw) ?? .zero
    }
}
