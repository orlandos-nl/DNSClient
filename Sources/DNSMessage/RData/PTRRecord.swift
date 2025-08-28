import NIOCore

/// A DNS PTR record. This is used for address to name mapping.
public struct PTRRecord: DNSResource {
    /// A  domain-name which points to some location in the domain name space.
    public let domainName: [DNSLabel]

    public static func read(from buffer: inout ByteBuffer, length: Int) -> PTRRecord? {
        guard let domainName = buffer.readLabels() else {
            return nil
        }
        return PTRRecord(domainName: domainName)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        buffer.writeCompressedLabels(domainName, labelIndices: &labelIndices)
    }

    public init(domainName: [DNSLabel]) {
        self.domainName = domainName
    }
}

extension PTRRecord: CustomStringConvertible {
    public var description: String {
        "\(Self.self): " + domainName.string
    }
}
