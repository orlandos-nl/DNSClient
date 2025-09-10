import NIOCore

/// A mail exchange record. This is used for mail servers.
public struct MXRecord: DNSResource {
    /// The preference of the mail server. This is used to determine which mail server to use.
    public let preference: Int

    /// The labels of the mail server.
    public let labels: [DNSLabel]

    public static func read(from buffer: inout ByteBuffer, length: Int) -> MXRecord? {
        guard let preference = buffer.readInteger(endianness: .big, as: UInt16.self) else { return nil }

        guard let labels = buffer.readLabels() else {
            return nil
        }

        return MXRecord(preference: Int(preference), labels: labels)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        let length = buffer.writeInteger(preference)
        return length + buffer.writeCompressedLabels(labels, labelIndices: &labelIndices)
    }
}
