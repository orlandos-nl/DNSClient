import NIO
public import NIOCore

#if os(Linux)
import CNIOLinux
#endif

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
    public let bytes: [UInt8]

    public var description: String {
        var addr = in6_addr()
        #if os(Linux)
        withUnsafeMutableBytes(of: &addr.__in6_u.__u6_addr8) { ptr in
            ptr.copyBytes(from: self.bytes)
        }
        #else
        withUnsafeMutableBytes(of: &addr.__u6_addr.__u6_addr8) { ptr in
            ptr.copyBytes(from: self.bytes)
        }
        #endif
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result = inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))!
        return String(cString: result)
    }

    public static var name: String { "AAAA" }
    public static var encoding: DNSRDataEncoding { .other }
    public static var resourceType: DNSResourceType { .aaaa }

    public static func == (lhs: AAAARecord, rhs: AAAARecord) -> Bool {
        lhs.bytes == rhs.bytes
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length == 16 else {
            throw DNSMessageError.invalidFormat(field: "AAAA record length", reason: "expected 16 bytes, got \(length)")
        }

        guard let address = decoder.buffer.readBytes(length: length) else {
            throw DNSMessageError.insufficientData(expected: 16, available: decoder.buffer.readableBytes)
        }

        self.init(bytes: address)
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
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

        self.bytes = bytes
    }

    public init(address: some Collection<UInt8>) throws {
        guard address.count == 16 else {
            throw DNSMessageError.invalidFormat(
                field: "IPv6 address bytes",
                reason: "Expected 16 bytes, got \(address.count)"
            )
        }

        self.bytes = Array(address)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        encoder.buffer.writeBytes(self.bytes)
    }

    /// Converts the IPv6 address to a SocketAddress. This is used for converting the address of a DNS record to a SocketAddress.
    public func socketAddress(port: Int) throws -> SocketAddress {
        try SocketAddress(ipBytes: self.bytes, port: port)
    }
}
