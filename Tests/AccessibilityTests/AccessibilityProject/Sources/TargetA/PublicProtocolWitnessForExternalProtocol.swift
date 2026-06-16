import Foundation

// The protocol refines the external/stdlib `Identifiable` protocol. The `id` witness is
// supplied as a default implementation in the extension below. Because `Identifiable` is a
// public protocol, the witness must remain public, otherwise the compiler emits:
// "property 'id' must be declared public because it matches a requirement in public protocol
// 'Identifiable'".
public protocol PublicProtocolWitnessForExternalProtocol: Identifiable {}

public extension PublicProtocolWitnessForExternalProtocol {
    var id: String { String(describing: self) }
}

public enum PublicProtocolWitnessForExternalProtocolEnum: String, PublicProtocolWitnessForExternalProtocol {
    case first
    case second
}

public class PublicProtocolWitnessForExternalProtocolRetainer {
    public init() {}
    public func retain() {
        _ = PublicProtocolWitnessForExternalProtocolEnum.first.id
    }
}
