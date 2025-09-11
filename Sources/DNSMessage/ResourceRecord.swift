import NIOCore

public protocol DNSRecordProtocol: CustomStringConvertible, Sendable, Equatable {
    var name: DNSName { get }
    var rrType: DNSResourceType { get }
    var recordClass: DNSClass { get }
    var ttl: UInt32 { get }
    var rDataErased: any DNSResourceData { get }
}

extension DNSRecordProtocol {
    public func isEqual(_ other: any DNSRecordProtocol) -> Bool {
        self.name == other.name && self.rrType == other.rrType
            && self.recordClass == other.recordClass && self.ttl == other.ttl
            && self.rDataErased.isEqual(to: other.rDataErased)
    }

    public func rData<T: DNSResourceData>(as type: T.Type) -> T? {
        rDataErased as? T
    }

    public func asResourceRecord<T: DNSResourceData>(_ type: T.Type) -> DNSResourceRecord<T>? {
        guard let typedData = rDataErased as? T else { return nil }
        return try? DNSResourceRecord(
            name: self.name,
            rrType: self.rrType,
            recordClass: self.recordClass,
            ttl: self.ttl,
            rData: typedData
        )
    }
}

/// A protocol that can be used to read a DNS resource from a buffer.
public protocol DNSResourceData: Sendable, CustomStringConvertible, Equatable {
    static var encoding: DNSRDataEncoding { get }
    static var resourceType: DNSResourceType { get }

    /// The string name of the DNS resource type
    static var name: String { get }

    init(from decoder: inout DNSDecoder, length: Int) throws
    func write(encoder: inout DNSEncoder) throws -> Int

    func isEqual(to other: any DNSResourceData) -> Bool
}

extension DNSResourceData {
    public func isEqual(to other: any DNSResourceData) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

/// Determines how DNS resource record data (RDATA) should be encoded, particularly how domain names
/// within the RDATA are handled. The encoding rules evolved over time through various RFCs.
public struct DNSRDataEncoding: Equatable, Hashable, Sendable {
    public internal(set) var rawValue: UInt8

    public static var standardRecord: Self { .init(rawValue: 0) }
    public static var other: Self { .init(rawValue: 1) }
    public static var canonical: Self { .init(rawValue: 2) }

    func toNameEncoding() -> DNSNameEncoding {
        switch self {
        case .standardRecord:
            return .compressed
        case .other:
            return .uncompressed
        case .canonical:
            return .uncompressedLowercase
        default:
            return .uncompressedLowercase
        }
    }
}

/// [RFC 1035 DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION](https://tools.ietf.org/html/rfc1035)
///
/// ```txt
/// All RRs have the same top level format shown below:
///
///                                     1  1  1  1  1  1
///       0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                                               |
///     /                                               /
///     /                      NAME                     /
///     |                                               |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                      TYPE                     |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                     CLASS                     |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                      TTL                      |
///     |                                               |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                   RDLENGTH                    |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--|
///     /                     RDATA                     /
///     /                                               /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///
///
/// where:
///
/// NAME            an owner name, i.e., the name of the node to which this
///                 resource record pertains.
///
/// TYPE            two octets containing one of the RR TYPE codes.
///
/// CLASS           two octets containing one of the RR CLASS codes.
///
/// TTL             a 32 bit signed integer that specifies the time interval
///                 that the resource record may be cached before the source
///                 of the information should again be consulted.  Zero
///                 values are interpreted to mean that the RR can only be
///                 used for the transaction in progress, and should not be
///                 cached.  For example, SOA records are always distributed
///                 with a zero TTL to prohibit caching.  Zero values can
///                 also be used for extremely volatile data.
///
/// RDLENGTH        an unsigned 16 bit integer that specifies the length in
///                 octets of the RDATA field.
///
/// RDATA           a variable length string of octets that describes the
///                 resource.  The format of this information varies
///                 according to the TYPE and CLASS of the resource record.
/// ```
public struct DNSResourceRecord<ResourceData: DNSResourceData>: DNSRecordProtocol {
    public var name: DNSName
    public var rrType: DNSResourceType
    public var recordClass: DNSClass
    public var ttl: UInt32
    public var rData: ResourceData
    public var rDataErased: any DNSResourceData { self.rData }

    public var description: String {
        "\(self.name) \(self.ttl) \(String(describing: self.recordClass)) \(ResourceData.name) \(String(describing: self.rData))"
    }

    public init(
        name: DNSName,
        rrType: DNSResourceType,
        recordClass: DNSClass,
        ttl: UInt32,
        rData: ResourceData
    ) throws {
        guard rrType.isValidInRR else {
            throw DNSMessageError.invalidResourceRecordType(rrType)
        }

        self.name = name
        self.rrType = rrType
        self.recordClass = recordClass
        self.ttl = ttl
        self.rData = rData
    }
}

public struct DNSRecord: DNSRecordProtocol, Sendable, Equatable {
    public var name: DNSName
    public var rrType: DNSResourceType
    public var recordClass: DNSClass
    public var ttl: UInt32
    public var rDataErased: any DNSResourceData

    public var description: String {
        "\(self.name) \(self.ttl) \(String(describing: self.recordClass)) \(DNSResourceType.getTypeName(for: self.rrType)) \(String(describing: self.rDataErased))"
    }

    public init<ResourceData: DNSResourceData>(_ record: DNSResourceRecord<ResourceData>) {
        self.name = record.name
        self.rrType = record.rrType
        self.recordClass = record.recordClass
        self.ttl = record.ttl
        self.rDataErased = record.rData
    }

    public init(
        name: DNSName,
        rrType: DNSResourceType,
        dnsClass: DNSClass,
        ttl: UInt32,
        rData: any DNSResourceData
    ) throws {
        guard rrType.isValidInRR else {
            throw DNSMessageError.invalidResourceRecordType(rrType)
        }

        self.name = name
        self.rrType = rrType
        self.recordClass = dnsClass
        self.ttl = ttl
        self.rDataErased = rData
    }

    public static func == (lhs: DNSRecord, rhs: DNSRecord) -> Bool {
        lhs.isEqual(rhs)
    }

    public static func == <ResourceData: DNSResourceData>(
        lhs: DNSRecord,
        rhs: DNSResourceRecord<ResourceData>
    ) -> Bool {
        lhs.isEqual(rhs)
    }

    public static func == <ResourceData: DNSResourceData>(
        lhs: DNSResourceRecord<ResourceData>,
        rhs: DNSRecord
    ) -> Bool {
        lhs.isEqual(rhs)
    }
}

@available(
    *,
    deprecated,
    message: """
        ResourceRecord has been replaced with DNSResourceRecord for improved type safety and API consistency.

        Migration guide:
        - Use DNSResourceRecord<T> for typed records where T conforms to DNSResourceData
        - Use DNSRecord for type-erased records
        - Replace ResourceRecord<Resource> with DNSResourceRecord<ResourceData>
        """
)
public typealias ResourceRecord = DNSResourceRecord
@available(
    *,
    deprecated,
    message: """
        Record has been replaced with DNSRecord for improved type safety and API consistency.

        Migration guide:
        - Use DNSRecord for type-erased records
        - Use DNSResourceRecord<T> for typed records where T conforms to DNSResourceData
        - Replace Record enum cases with DNSRecord instances
        """
)
public typealias Record = DNSRecord
