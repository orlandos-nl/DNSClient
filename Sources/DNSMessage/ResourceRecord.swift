import NIOCore

/// A protocol that can be used to read a DNS resource from a buffer.
public protocol DNSResource: Sendable {
    static func read(from buffer: inout ByteBuffer, length: Int) -> Self?
    func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int
}

/// A structure representing a DNS resource record. This is used for storing the data of a DNS record.
public struct ResourceRecord<Resource: DNSResource>: Sendable {
    /// The name of the record.
    public let domainName: [DNSLabel]

    /// The type of the record. See `RecordType` for more information.
    public let dataType: UInt16

    /// The class of the record. This is usually 1 for internet. See `DataClass` for more information.
    public let dataClass: UInt16

    /// The time to live of the record. This is the amount of time the record should be cached for.
    public let ttl: UInt32

    /// The resource of the record. This is the data of the record.
    public var resource: Resource

    public init(
        domainName: [DNSLabel],
        dataType: UInt16,
        dataClass: UInt16,
        ttl: UInt32,
        resource: Resource
    ) {
        self.domainName = domainName
        self.dataType = dataType
        self.dataClass = dataClass
        self.ttl = ttl
        self.resource = resource
    }
}

/// An extension to `ByteBuffer` that adds a method for reading a DNS resource.
extension ByteBuffer: DNSResource {
    public static func read(from buffer: inout ByteBuffer, length: Int) -> ByteBuffer? {
        buffer.readSlice(length: length)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        buffer.writeImmutableBuffer(self)
    }
}

/// A DNS message. This is the main type used for interacting with the DNS protocol.
public enum Record {
    /// An IPv6 address record. This is used for resolving hostnames to IP addresses.
    case aaaa(ResourceRecord<AAAARecord>)

    /// An IPv4 address record. This is used for resolving hostnames to IP addresses.
    case a(ResourceRecord<ARecord>)

    /// A text record. This is used for storing arbitrary text.
    case txt(ResourceRecord<TXTRecord>)

    /// A CNAME record. This is used for aliasing hostnames.
    case cname(ResourceRecord<CNAMERecord>)

    /// A service record. This is used for service discovery.
    case srv(ResourceRecord<SRVRecord>)

    /// Mail exchange record. This is used for mail servers.
    case mx(ResourceRecord<MXRecord>)

    /// A domain name pointer (ie. in-addr.arpa)
    case ptr(ResourceRecord<PTRRecord>)

    /// an authoritative name server
    case ns(ResourceRecord<NSRecord>)

    /// marks the start of authority for a zone
    case soa(ResourceRecord<SOARecord>)

    /// Any other record. This is used for records that are not yet supported through convenience methods.
    case other(ResourceRecord<ByteBuffer>)
}
