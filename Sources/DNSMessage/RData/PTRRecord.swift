import NIOCore

/// [RFC 1035, DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION, November 1987](https://tools.ietf.org/html/rfc1035)
///
/// 3.3.12. PTR RDATA format
///
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                   PTRDNAME                    /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///
/// where:
///
/// PTRDNAME        A <domain-name> which points to some location in the
///                 domain name space.
///
/// PTR records cause no additional section processing.  These RRs are used
/// in special domains to point to some other location in the domain space.
/// These records are simple data, and don't imply any special processing
/// similar to that performed by CNAME, which identifies aliases.  See the
/// description of the IN-ADDR.ARPA domain for an example.
public struct PTRRecord: DNSResourceData {
    public var targetDomainName: DNSName

    public var description: String {
        "\(String(describing: targetDomainName))"
    }

    public static var name: String { "PTR" }
    public static var encoding: DNSRDataEncoding { .standardRecord }
    public static var resourceType: DNSResourceType { .ptr }

    public init(targetDomainName: DNSName) {
        self.targetDomainName = targetDomainName
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        self.targetDomainName = DNSName()
        try decoder.readDNSName(name: &self.targetDomainName)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        try encoder.writeDNSName(self.targetDomainName)
    }
}
