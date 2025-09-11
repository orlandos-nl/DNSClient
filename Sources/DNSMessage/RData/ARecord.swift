import NIO
public import NIOCore

/// [RFC 1035, DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION, November 1987](https://tools.ietf.org/html/rfc1035)
///
/// 3.4.1. A RDATA format
/// ```
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                    ADDRESS                    |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// ```
/// where:
///
/// ADDRESS         A 32 bit Internet address.
public struct ARecord: DNSResourceData {
    public let ipv4Address: [UInt8]
    private let _socketAddress: SocketAddress

    public var description: String {
        "\(_socketAddress.ipAddress ?? "<invalid IPv4>")"
    }

    public static var name: String { "A" }
    public static var encoding: DNSRDataEncoding { .standardRecord }
    public static var resourceType: DNSResourceType { .a }

    public static func == (lhs: ARecord, rhs: ARecord) -> Bool {
        lhs.ipv4Address == rhs.ipv4Address
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length == 4 else {
            throw DNSMessageError.invalidFormat(field: "A record length", reason: "expected 4 bytes, got \(length)")
        }

        guard let address = decoder.buffer.readBytes(length: length) else {
            throw DNSMessageError.insufficientData(expected: 4, available: decoder.buffer.readableBytes)
        }

        self.init(ipv4Address: address, socketAddress: try SocketAddress(ipBytes: address, port: 0))
    }

    private init(ipv4Address: [UInt8], socketAddress: SocketAddress) {
        self.ipv4Address = ipv4Address
        self._socketAddress = socketAddress
    }

    public init(address: String) throws {
        var addr = in_addr()
        let result = address.withCString { cString in
            inet_pton(AF_INET, cString, &addr)
        }

        guard result == 1 else {
            throw DNSMessageError.invalidFormat(
                field: "IPv4 address",
                reason: "Invalid IPv4 address format: \(address)"
            )
        }

        let bytes = withUnsafeBytes(of: addr.s_addr) { Array($0) }

        self.ipv4Address = bytes
        self._socketAddress = try SocketAddress(ipBytes: bytes, port: 0)
    }

    public init(address: [UInt8]) throws {
        guard address.count == 4 else {
            throw DNSMessageError.invalidFormat(
                field: "IPv4 address bytes",
                reason: "Expected 4 bytes, got \(address.count)"
            )
        }

        self.ipv4Address = address
        self._socketAddress = try SocketAddress(ipBytes: address, port: 0)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        encoder.buffer.writeBytes(self.ipv4Address)
    }

    /// Converts the IPv4 address to a SocketAddress. This is used for converting the address of a DNS record to a SocketAddress.
    public func socketAddress(port: Int) throws -> SocketAddress {
        try SocketAddress(ipAddress: _socketAddress.ipAddress!, port: port)
    }

    /// Check if this is a multicast address
    public var isMulticast: Bool {
        self._socketAddress.isMulticast
    }
}
