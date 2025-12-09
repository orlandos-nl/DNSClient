import NIO
public import NIOCore

#if os(Linux)
import CNIOLinux
#endif

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
    public let bytes: [UInt8]

    public var description: String {
        var addr = in_addr()
        withUnsafeMutableBytes(of: &addr.s_addr) { ptr in
            ptr.copyBytes(from: self.bytes)
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let result = inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))!
        return String(cString: result)
    }

    public static var name: String { "A" }
    public static var encoding: DNSRDataEncoding { .standardRecord }
    public static var resourceType: DNSResourceType { .a }

    public static func == (lhs: ARecord, rhs: ARecord) -> Bool {
        lhs.bytes == rhs.bytes
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length == 4 else {
            throw DNSMessageError.invalidFormat(field: "A record length", reason: "expected 4 bytes, got \(length)")
        }

        guard let address = decoder.buffer.readBytes(length: length) else {
            throw DNSMessageError.insufficientData(expected: 4, available: decoder.buffer.readableBytes)
        }

        self.init(ipv4Address: address)
    }

    private init(ipv4Address: [UInt8]) {
        self.bytes = ipv4Address
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

        self.bytes = bytes
    }

    public init(address: some Collection<UInt8>) throws {
        guard address.count == 4 else {
            throw DNSMessageError.invalidFormat(
                field: "IPv4 address bytes",
                reason: "Expected 4 bytes, got \(address.count)"
            )
        }

        self.bytes = Array(address)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        encoder.buffer.writeBytes(self.bytes)
    }

    /// Converts the IPv4 address to a SocketAddress. This is used for converting the address of a DNS record to a SocketAddress.
    public func socketAddress(port: Int) throws -> SocketAddress {
        try SocketAddress(ipBytes: self.bytes, port: port)
    }
}
