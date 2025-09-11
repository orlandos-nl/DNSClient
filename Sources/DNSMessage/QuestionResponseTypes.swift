/// The type of resource record. This is used to determine the format of the record.
///
/// The official standard list of all Resource Record (RR) Types. [IANA](https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml#dns-parameters-4)
public struct DNSResourceType: Equatable, Hashable, Sendable {
    public var rawValue: UInt16
    private static var registeredTypes: [Self: any DNSResourceData.Type] = [
        .a: ARecord.self,
        .ns: NSRecord.self,
        .cname: CNAMERecord.self,
        .soa: SOARecord.self,
        .null: NULLRecord.self,
        .ptr: PTRRecord.self,
        .hinfo: HINFORecord.self,
        .mx: MXRecord.self,
        .txt: TXTRecord.self,
        .aaaa: AAAARecord.self,
        .srv: SRVRecord.self,
        .svcb: SVCBRecord.self,
        .https: HTTPSRecord.self,
    ]

    public static var a = Self(rawValue: 1)
    public static let ns = Self(rawValue: 2)
    public static let cname = Self(rawValue: 5)
    public static let soa = Self(rawValue: 6)
    public static let null = Self(rawValue: 10)
    public static let ptr = Self(rawValue: 12)
    public static let hinfo = Self(rawValue: 13)
    public static let mx = Self(rawValue: 15)
    public static let txt = Self(rawValue: 16)
    public static let aaaa = Self(rawValue: 28)
    public static let srv = Self(rawValue: 33)
    public static let opt = Self(rawValue: 41)
    public static let svcb = Self(rawValue: 64)
    public static let https = Self(rawValue: 65)
    public static let ixfr = Self(rawValue: 251)
    public static let axfr = Self(rawValue: 252)
    public static let any = Self(rawValue: 255)

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    // Register a custom RecordData (returns false if type already exists)
    public static func register<T: DNSResourceData>(_ type: T.Type) -> Bool {
        if registeredTypes[T.resourceType] != nil {
            return false
        }
        registeredTypes[T.resourceType] = type
        return true
    }

    // Override an existing RecordData type
    public static func override<T: DNSResourceData>(_ type: T.Type) {
        registeredTypes[T.resourceType] = type
    }

    package static func registeredType(for type: DNSResourceType) -> any DNSResourceData.Type {
        registeredTypes[type] ?? NULLRecord.self
    }

    public static func getTypeName(for type: DNSResourceType) -> String {
        registeredTypes[type]?.name ?? "TYPE(\(type.rawValue))"
    }

    internal var isValidInRR: Bool {
        switch rawValue {
        case 1...127, 256...61439:  // Data types only
            return true
        case 65280...65534:  // Private use - could be data
            return true
        default:
            return false
        }
    }

    internal var isValidInQuestion: Bool {
        switch rawValue {
        case 0, 65535:  // Reserved - invalid
            return false
        case 1...65534:  // Everything else is valid
            return true
        default:
            return false
        }
    }
}

/// The class of the resource record. This is used to determine the format of the record.
public struct DNSClass: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var rawValue: UInt16

    public static var internet: Self { .init(rawValue: 1) }
    public static var chaos: Self { .init(rawValue: 3) }
    public static var hesiod: Self { .init(rawValue: 4) }
    public static var none: Self { .init(rawValue: 254) }
    public static var any: Self { .init(rawValue: 255) }

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public var description: String {
        switch self {
        case .internet:
            return "IN"
        case .chaos:
            return "CH"
        case .hesiod:
            return "HS"
        case .none:
            return "NONE"
        case .any:
            return "ANY"
        default:
            return "\(self.rawValue)"
        }
    }

    internal var isValidInQuestion: Bool {
        switch rawValue {
        case 0, 65535:  // Reserved - invalid
            return false
        case 1...65534:  // Everything else is valid
            return true
        default:
            return false
        }
    }

    internal var isValidInRR: Bool {
        switch rawValue {
        case 1...127, 32768...57343:  // Data classes only
            return true
        case 65280...65534:  // Private use - could be data
            return true
        default:
            return false
        }
    }
}

@available(*, deprecated, renamed: "DNSClass")
public typealias DataClass = DNSClass
