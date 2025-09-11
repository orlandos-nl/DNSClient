import NIOCore

/// [RFC 1035, DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION, November 1987](https://tools.ietf.org/html/rfc1035)
///
/// ```text
/// 3.3.13. SOA RDATA format
///
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                     MNAME                     /
///     /                                               /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                     RNAME                     /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                    SERIAL                     |
///     |                                               |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                    REFRESH                    |
///     |                                               |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                     RETRY                     |
///     |                                               |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                    EXPIRE                     |
///     |                                               |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                    MINIMUM                    |
///     |                                               |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///
/// where:
///
/// SOA records cause no additional section processing.
///
/// All times are in units of seconds.
///
/// Most of these fields are pertinent only for name server maintenance
/// operations.  However, MINIMUM is used in all query operations that
/// retrieve RRs from a zone.  Whenever a RR is sent in a response to a
/// query, the TTL field is set to the maximum of the TTL field from the RR
/// and the MINIMUM field in the appropriate SOA.  Thus MINIMUM is a lower
/// bound on the TTL field for all RRs in a zone.  Note that this use of
/// MINIMUM should occur when the RRs are copied into the response and not
/// when the zone is loaded from a Zone File or via a zone transfer.  The
/// reason for this provision is to allow future dynamic update facilities to
/// change the SOA RR with known semantics.
/// ```
public struct SOARecord: DNSResourceData {
    // Main Name Server - specifies the fully qualified domain name (FQDN)
    // of the authoritative name server for the zone that holds the master copy of the zone file.
    public var mname: DNSName

    // Responsible Person Name - and specifies the email address of the administrator responsible
    // for the DNS zone. This field contains an email address but without the "@" symbol,
    // where the first unescaped dot (.) is interpreted as an "@" sign
    public var rname: DNSName

    // Serial Number - This is a version number for the zone file,
    // a database that contains all of the DNS records for a domain.
    public var serialNumber: UInt32

    public var refreshInterval: Int32
    public var retryInterval: Int32
    public var expireInterval: Int32
    public var minimumTTL: UInt32

    public var description: String {
        "\(String(describing: mname)) \(String(describing: rname)) \(serialNumber) \(refreshInterval) \(retryInterval) \(expireInterval) \(minimumTTL)"
    }

    public static let name: String = "SOA"
    public static let encoding: DNSRDataEncoding = .standardRecord
    public static let resourceType: DNSResourceType = .soa

    public init(
        mname: DNSName,
        rname: DNSName,
        serialNumber: UInt32,
        refreshInterval: Int32,
        retryInterval: Int32,
        expireInterval: Int32,
        minimumTTL: UInt32
    ) {
        self.mname = mname
        self.rname = rname
        self.serialNumber = serialNumber
        self.refreshInterval = refreshInterval
        self.retryInterval = retryInterval
        self.expireInterval = expireInterval
        self.minimumTTL = minimumTTL
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        self.mname = DNSName()
        self.rname = DNSName()
        try decoder.readDNSName(name: &self.mname)
        try decoder.readDNSName(name: &self.rname)
        guard
            let serialNumber: UInt32 = decoder.buffer.readInteger(),
            let refreshInterval: Int32 = decoder.buffer.readInteger(),
            let retryInterval: Int32 = decoder.buffer.readInteger(),
            let expireInterval: Int32 = decoder.buffer.readInteger(),
            let minimumInterval: UInt32 = decoder.buffer.readInteger()
        else {
            throw DNSMessageError.insufficientData(expected: 20, available: decoder.buffer.readableBytes)
        }

        self.serialNumber = serialNumber
        self.refreshInterval = refreshInterval
        self.retryInterval = retryInterval
        self.expireInterval = expireInterval
        self.minimumTTL = minimumInterval
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        var written = 0

        written += try encoder.writeDNSName(self.mname)
        written += try encoder.writeDNSName(self.rname)
        written += encoder.buffer.writeInteger(self.serialNumber)
        written += encoder.buffer.writeInteger(self.refreshInterval)
        written += encoder.buffer.writeInteger(self.retryInterval)
        written += encoder.buffer.writeInteger(self.expireInterval)
        written += encoder.buffer.writeInteger(self.minimumTTL)

        return written
    }
}
