import NIOCore

/// NS Record - an authoritativename server
/// /// 3.3.11. SOA RDATA format - https://www.rfc-editor.org/rfc/rfc1035.html
public struct NSRecord: DNSResource {
    public let labels: [DNSLabel]

    public static func read(from buffer: inout ByteBuffer, length: Int) -> NSRecord? {
        guard let labels = buffer.readLabels() else { return nil }
        return NSRecord(labels: labels)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        buffer.writeCompressedLabels(labels, labelIndices: &labelIndices)
    }
}
