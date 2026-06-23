import Foundation

// Mirrors the Prodcore DirectFilePlaybackController false positive: a concrete type conforms to an
// in-module protocol and is itself reachable, but its witness methods have no caller via the protocol
// type. The witnesses must be retained — removing them produces "type does not conform to protocol".
protocol FixtureTransport310: AnyObject {
    var isPlaying: Bool { get }
    func play()
    func pause()
}

final class FixturePlayer310: FixtureTransport310 {
    var isPlaying: Bool = false
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
}

// Keep the conforming type reachable WITHOUT calling play()/pause() through the protocol — mirrors the
// real case where the type is constructed/held but its transport methods have no live call site.
public enum FixturePlayer310Holder {
    public static func make() -> AnyObject {
        FixturePlayer310()
    }
}
