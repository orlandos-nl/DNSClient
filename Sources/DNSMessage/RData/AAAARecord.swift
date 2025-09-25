import NIO
public import NIOCore

/// [RFC 3596, DNS Extensions to Support IP Version 6, October 2003](https://tools.ietf.org/html/rfc3596)
///
/// 2.1 AAAA record type
/// ```
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                                               |
///     |                    ADDRESS                    |
///     |                                               |
///     |                                               |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// ```
/// where:
///
/// ADDRESS         A 128 bit IPv6 address.
public struct AAAARecord: DNSResourceData {
    public let ipv6Address: [UInt8]
    private let _socketAddress: SocketAddress

    public var description: String {
        "\(_socketAddress.ipAddress ?? "<invalid IPv6>")"
    }

    public static var name: String { "AAAA" }
    public static var encoding: DNSRDataEncoding { .other }
    public static var resourceType: DNSResourceType { .aaaa }

    public static func == (lhs: AAAARecord, rhs: AAAARecord) -> Bool {
        lhs.ipv6Address == rhs.ipv6Address
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length == 16 else {
            throw DNSMessageError.invalidFormat(field: "AAAA record length", reason: "expected 16 bytes, got \(length)")
        }

        guard let address = decoder.buffer.readBytes(length: length) else {
            throw DNSMessageError.insufficientData(expected: 16, available: decoder.buffer.readableBytes)
        }

        self.init(ipv6Address: address, socketAddress: try SocketAddress(ipBytes: address, port: 0))
    }

    private init(ipv6Address: [UInt8], socketAddress: SocketAddress) {
        self.ipv6Address = ipv6Address
        self._socketAddress = socketAddress
    }

    public init(address: String) throws {
        var addr = in6_addr()
        let result = address.withCString { cString in
            inet_pton(AF_INET6, cString, &addr)
        }

        guard result == 1 else {
            throw DNSMessageError.invalidFormat(
                field: "IPv6 address",
                reason: "Invalid IPv6 address format: \(address)"
            )
        }

        #if os(Linux)
        let bytes = withUnsafeBytes(of: addr.__in6_u.__u6_addr8) { Array($0) }
        #else
        let bytes = withUnsafeBytes(of: addr.__u6_addr.__u6_addr8) { Array($0) }
        #endif

        self.ipv6Address = bytes
        self._socketAddress = try SocketAddress(ipBytes: bytes, port: 0)
    }

    public init(address: [UInt8]) throws {
        guard address.count == 16 else {
            throw DNSMessageError.invalidFormat(
                field: "IPv6 address bytes",
                reason: "Expected 16 bytes, got \(address.count)"
            )
        }

        self.ipv6Address = address
        self._socketAddress = try SocketAddress(ipBytes: address, port: 0)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        encoder.buffer.writeBytes(self.ipv6Address)
    }

    /// Converts the IPv6 address to a SocketAddress. This is used for converting the address of a DNS record to a SocketAddress.
    public func socketAddress(port: Int) throws -> SocketAddress {
        try SocketAddress(ipAddress: _socketAddress.ipAddress!, port: port)
    }

    /// Check if this is a multicast address
    public var isMulticast: Bool {
        _socketAddress.isMulticast
    }
}
