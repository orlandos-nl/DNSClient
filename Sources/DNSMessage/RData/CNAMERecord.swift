import NIOCore

/// [RFC 1035, DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION, November 1987](https://tools.ietf.org/html/rfc1035)
///
/// 3.3.1. CNAME RDATA format
///
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                     CNAME                     /
///     /                                               /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///
/// where:
///
/// CNAME           A <domain-name> which specifies the canonical or primary
///                 name for the owner.  The owner name is an alias.
///
/// CNAME RRs cause no additional section processing, but name servers may
/// choose to restart the query at the canonical name in certain cases.  See
/// the description of name server logic in [RFC-1034] for details.
public struct CNAMERecord: DNSResourceData {
    public var cname: DNSName

    public var description: String {
        "\(String(describing: cname))"
    }

    public static let name: String = "CNAME"
    public static let encoding: DNSRDataEncoding = .standardRecord
    public static let resourceType: DNSResourceType = .cname

    public init(cname: DNSName) {
        self.cname = cname
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        self.cname = DNSName()
        try decoder.readDNSName(name: &self.cname)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        try encoder.writeDNSName(self.cname)
    }
}
