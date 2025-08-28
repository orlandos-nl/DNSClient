import NIOCore

/// A canonical name record. This is used for aliasing hostnames.
public struct CNAMERecord: DNSResource {
    /// The labels of the alias.
    public let labels: [DNSLabel]

    public static func read(from buffer: inout ByteBuffer, length: Int) -> CNAMERecord? {
        guard let labels = buffer.readLabels() else {
            return nil
        }
        return CNAMERecord(labels: labels)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        buffer.writeCompressedLabels(labels, labelIndices: &labelIndices)
    }
}
