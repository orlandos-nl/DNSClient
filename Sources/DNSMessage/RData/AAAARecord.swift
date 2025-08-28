import NIOCore

/// An IPv6 address record. This is used for resolving hostnames to IP addresses.
public struct AAAARecord: DNSResource {
    /// The address of the record. This is a 128-bit integer.
    public let address: [UInt8]

    /// The address of the record as a string.
    public var stringAddress: String {
        String(
            format: "%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x",
            address[0],
            address[1],
            address[2],
            address[3],
            address[4],
            address[5],
            address[6],
            address[7],
            address[8],
            address[9],
            address[10],
            address[11],
            address[12],
            address[13],
            address[14],
            address[15]
        )
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> AAAARecord? {
        guard let address = buffer.readBytes(length: 16) else { return nil }
        return AAAARecord(address: address)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        buffer.writeBytes(address)
    }
}
