import SwiftUI

struct FixtureViewChild: View {
    let value: Int
    let action: () -> Void

    var body: some View {
        Button("\(value)", action: action)
    }
}

public struct FixtureViewParent: View {
    public init() {}

    private let items = [1, 2, 3]

    public var body: some View {
        VStack {
            ForEach(items, id: \.self) { item in
                helper(item: item)
            }
        }
    }

    @ViewBuilder
    private func helper(item: Int) -> some View {
        let derived = item * 2
        FixtureViewChild(value: derived, action: { print(derived) })
    }
}
