import NIO

/// An IPv4 address record. This is used for resolving hostnames to IP addresses.
public struct ARecord: DNSResource {
    /// The address of the record. This is a 32-bit integer.
    public let address: UInt32

    public init(address: UInt32) {
        self.address = address
    }

    /// The address of the record as a string.
    public var stringAddress: String {
        withUnsafeBytes(of: address) { buffer in
            let buffer = buffer.bindMemory(to: UInt8.self)
            return "\(buffer[3]).\(buffer[2]).\(buffer[1]).\(buffer[0])"
        }
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> ARecord? {
        guard let address = buffer.readInteger(endianness: .big, as: UInt32.self) else { return nil }
        return ARecord(address: address)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        buffer.writeInteger(address)
    }
}

extension UInt32 {
    /// Converts the UInt32 to a SocketAddress. This is used for converting the address of a DNS record to a SocketAddress.
    public func socketAddress(port: Int) throws -> SocketAddress {
        let text = inet_ntoa(in_addr(s_addr: self.bigEndian))!
        let host = String(cString: text)

        return try SocketAddress(ipAddress: host, port: port)
    }
}
