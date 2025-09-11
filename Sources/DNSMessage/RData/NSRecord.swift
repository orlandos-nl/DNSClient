import NIOCore

/// [RFC 1035, DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION, November 1987](https://tools.ietf.org/html/rfc1035)
///
/// 3.3.11. NS RDATA format
/// ```
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                   NSDNAME                     /
///     /                                               /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// ```
/// where:
///
/// NSDNAME         A <domain-name> which specifies a host which should be
///                 authoritative for the specified class and domain.
///
/// NS records cause both the usual additional section processing to locate
/// a type A record, and, when used in a referral, a special search of the
/// zone in which they reside for glue information.
///
/// The NS RR states that the named host should be expected to have a zone
/// starting at owner name of the specified class.  Note that the class may
/// not indicate the protocol family which should be used to communicate
/// with the host, although it is typically a strong hint.  For example,
/// hosts which are name servers for either Internet (IN) or Hesiod (HS)
/// class information are normally queried using IN class protocols..
public struct NSRecord: DNSResourceData {
    public var nsdname: DNSName

    public var description: String {
        "\(String(describing: nsdname))"
    }

    public static let name: String = "NS"
    public static let encoding: DNSRDataEncoding = .standardRecord
    public static let resourceType: DNSResourceType = .ns

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        self.nsdname = DNSName()
        try decoder.readDNSName(name: &self.nsdname)
    }

    public init(nsdname: DNSName) {
        self.nsdname = nsdname
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        try encoder.writeDNSName(self.nsdname)
    }
}
