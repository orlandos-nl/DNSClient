import NIOCore

/// SOA Record - marks the start of a zone of authority
/// 3.3.13. SOA RDATA format - https://www.rfc-editor.org/rfc/rfc1035.html
///
public struct SOARecord: DNSResource {
    // Main Name Server - specifies the fully qualified domain name (FQDN)
    // of the authoritative name server for the zone that holds the master copy of the zone file.
    public let mname: [DNSLabel]

    // Responsible Person Name - and specifies the email address of the administrator responsible
    // for the DNS zone. This field contains an email address but without the "@" symbol,
    // where the first unescaped dot (.) is interpreted as an "@" sign
    public let rname: [DNSLabel]

    // Serial Number - This is a version number for the zone file,
    // a database that contains all of the DNS records for a domain.
    public let serialNumber: UInt32

    public let refreshInterval: UInt32
    public let retryInterval: UInt32
    public let expireInterval: UInt32
    public let minimumTTL: UInt32

    public static func read(from buffer: inout ByteBuffer, length: Int) -> SOARecord? {
        guard
            let mname = buffer.readLabels(),
            let rname = buffer.readLabels(),
            let serial = buffer.readInteger(endianness: .big, as: UInt32.self),
            let refresh = buffer.readInteger(endianness: .big, as: UInt32.self),
            let retry = buffer.readInteger(endianness: .big, as: UInt32.self),
            let expire = buffer.readInteger(endianness: .big, as: UInt32.self),
            let minimum = buffer.readInteger(endianness: .big, as: UInt32.self)
        else { return nil }

        return SOARecord(
            mname: mname,
            rname: rname,
            serialNumber: serial,
            refreshInterval: refresh,
            retryInterval: retry,
            expireInterval: expire,
            minimumTTL: minimum
        )
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        var written = 0
        written += buffer.writeCompressedLabels(mname, labelIndices: &labelIndices)
        written += buffer.writeCompressedLabels(rname, labelIndices: &labelIndices)
        written += buffer.writeInteger(serialNumber)
        written += buffer.writeInteger(refreshInterval)
        written += buffer.writeInteger(retryInterval)
        written += buffer.writeInteger(expireInterval)
        written += buffer.writeInteger(minimumTTL)
        return written
    }
}
