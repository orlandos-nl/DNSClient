import NIOCore

/// [RFC 1035, DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION, November 1987](https://tools.ietf.org/html/rfc1035)
///
/// 3.3.9. MX RDATA format
///
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                  PREFERENCE                   |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                   EXCHANGE                    /
///     /                                               /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///
/// where:
///
/// PREFERENCE      A 16 bit integer which specifies the preference given to
///                 this RR among others at the same owner.  Lower values
///                 are preferred.
///
/// EXCHANGE        A <domain-name> which specifies a host willing to act as
///                 a mail exchange for the owner name.
///
/// MX records cause type A additional section processing for the host
/// specified by EXCHANGE.  The use of MX RRs is explained in detail in
/// [RFC-974].
public struct MXRecord: DNSResourceData {
    public var preference: UInt16
    public var exchange: DNSName

    public var description: String {
        "\(self.preference) \(self.exchange)"
    }

    public static var name: String { "MX" }
    public static var encoding: DNSRDataEncoding { .standardRecord }
    public static var resourceType: DNSResourceType { .mx }

    public init(preference: UInt16, exchange: DNSName) {
        self.preference = preference
        self.exchange = exchange
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard let preference: UInt16 = decoder.buffer.readInteger() else {
            throw DNSMessageError.insufficientData(expected: 2, available: decoder.buffer.readableBytes)
        }
        self.preference = preference
        self.exchange = DNSName()
        try decoder.readDNSName(name: &self.exchange)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        var written = 0

        written += encoder.buffer.writeInteger(self.preference)
        written += try encoder.writeDNSName(self.exchange)

        return written
    }
}
