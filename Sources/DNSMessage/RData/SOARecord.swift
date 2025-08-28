import NIOCore

struct ZoneAuthority {
    let domainName: [DNSLabel]
    let adminMail: String
    let serial: UInt32
    let refreshInterval: UInt32
    let retryTimeinterval: UInt32
    let expireTimeout: UInt32
    let minimumExpireTimeout: UInt32
}

private struct InvalidSOARecord: Error {}

/// An extension to `ResourceRecord` that adds a method for parsing a SOA record.
extension ResourceRecord where Resource == ByteBuffer {
    mutating func parseSOA() throws -> ZoneAuthority {
        guard
            let domainName = resource.readLabels(),
            resource.readableBytes >= 20,  // Minimum 5 UInt32's
            let serial: UInt32 = resource.readInteger(endianness: .big),
            let refresh: UInt32 = resource.readInteger(endianness: .big),
            let retry: UInt32 = resource.readInteger(endianness: .big),
            let expire: UInt32 = resource.readInteger(endianness: .big),
            let minimumExpire: UInt32 = resource.readInteger(endianness: .big)
        else {
            throw InvalidSOARecord()
        }

        return ZoneAuthority(
            domainName: domainName,
            adminMail: "",
            serial: serial,
            refreshInterval: refresh,
            retryTimeinterval: retry,
            expireTimeout: expire,
            minimumExpireTimeout: minimumExpire
        )
    }
}
