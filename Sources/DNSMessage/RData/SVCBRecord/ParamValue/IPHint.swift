import Foundation
import NIOCore

/// [RFC 9460 SVCB and HTTPS Resource Records](https://www.rfc-editor.org/rfc/rfc9460.html#name-ipv4hint-and-ipv6hint)
///
/// ```text
/// 7.3.  "ipv4hint" and "ipv6hint"
///
///    The "ipv4hint" and "ipv6hint" keys convey IP addresses that clients
///    MAY use to reach the service.  If A and AAAA records for TargetName
///    are locally available, the client SHOULD ignore these hints.
///    Otherwise, clients SHOULD perform A and/or AAAA queries for
///    TargetName per Section 3, and clients SHOULD use the IP address in
///    those responses for future connections.  Clients MAY opt to terminate
///    any connections using the addresses in hints and instead switch to
///    the addresses in response to the TargetName query.  Failure to use A
///    and/or AAAA response addresses could negatively impact load balancing
///    or other geo-aware features and thereby degrade client performance.
///
///    The presentation value SHALL be a comma-separated list (Appendix A.1)
///    of one or more IP addresses of the appropriate family in standard
///    textual format [RFC5952] [RFC4001].  To enable simpler parsing, this
///    SvcParamValue MUST NOT contain escape sequences.
///
///    The wire format for each parameter is a sequence of IP addresses in
///    network byte order (for the respective address family).  Like an A or
///    AAAA RRset, the list of addresses represents an unordered collection,
///    and clients SHOULD pick addresses to use in a random order.  An empty
///    list of addresses is invalid.
///
///    When selecting between IPv4 and IPv6 addresses to use, clients may
///    use an approach such as Happy Eyeballs [HappyEyeballsV2].  When only
///    "ipv4hint" is present, NAT64 clients may synthesize IPv6 addresses as
///    specified in [RFC7050] or ignore the "ipv4hint" key and wait for AAAA
///    resolution (Section 3).  For best performance, server operators
///    SHOULD include an "ipv6hint" parameter whenever they include an
///    "ipv4hint" parameter.
///
///    These parameters are intended to minimize additional connection
///    latency when a recursive resolver is not compliant with the
///    requirements in Section 4 and SHOULD NOT be included if most clients
///    are using compliant recursive resolvers.  When TargetName is the
///    service name or the owner name (which can be written as "."), server
///    operators SHOULD NOT include these hints, because they are unlikely
///    to convey any performance benefit.
/// ```
public struct SVCIPv4Hint: SVCParamValue {
    public var addresses: [ARecord]

    public var description: String {
        self.addresses.lazy.map({
            String(describing: $0)
        }).joined(separator: ",")
    }

    public static var correspondingKey: SVCParamKey { .ipv4Hint }
    public static var name: String { "ipv4hint" }

    public init(addresses: [ARecord]) {
        self.addresses = addresses
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length >= 4 else {
            throw DNSMessageError.invalidFormat(field: "SVC IPv4Hint", reason: "length must be at least 4 bytes")
        }

        guard length % 4 == 0 else {
            throw DNSMessageError.invalidFormat(field: "SVC IPv4Hint", reason: "length must be multiple of 4")
        }

        let addresses: [ARecord] = try (0..<length / 4).map({ _ in
            try ARecord(from: &decoder, length: 4)
        })

        self.addresses = addresses
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        guard !addresses.isEmpty else {
            throw DNSMessageError.emptyRequiredCollection("SVCIPv4Hint addresses")
        }

        var written = 0

        for address in self.addresses {
            written += try address.write(encoder: &encoder)
        }

        return written
    }
}

/// See `SVCIPv4Hint`
public struct SVCIPv6Hint: SVCParamValue {
    public var addresses: [AAAARecord]

    public var description: String {
        self.addresses.lazy.map({
            String(describing: $0)
        }).joined(separator: ",")
    }

    public static var correspondingKey: SVCParamKey { .ipv6Hint }
    public static var name: String { "ipv6hint" }

    public init(addresses: [AAAARecord]) {
        self.addresses = addresses
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length >= 16 else {
            throw DNSMessageError.invalidFormat(field: "SVC IPv6Hint", reason: "length must be at least 16 bytes")
        }

        guard length % 16 == 0 else {
            throw DNSMessageError.invalidFormat(field: "SVC IPv6Hint", reason: "length must be multiple of 16")
        }

        let addresses: [AAAARecord] = try (0..<length / 16).map({ _ in
            try AAAARecord(from: &decoder, length: 16)
        })

        self.addresses = addresses
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        guard !addresses.isEmpty else {
            throw DNSMessageError.emptyRequiredCollection("SVCIPv6Hint addresses")
        }

        var written = 0

        for address in self.addresses {
            written += try address.write(encoder: &encoder)
        }

        return written
    }
}
