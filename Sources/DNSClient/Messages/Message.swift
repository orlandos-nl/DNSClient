import NIO
import Foundation

/// The header of a DNS message.
public struct DNSMessageHeader {
    /// The ID of the message. This is used to match responses to requests.
    public internal(set) var id: UInt16
    
    /// The flags of the message.
    public let options: MessageOptions
    
    /// The number of questions in the message.
    public let questionCount: UInt16

    /// The number of answers in the message.
    public let answerCount: UInt16

    /// The number of authorities in the message.
    public let authorityCount: UInt16

    /// The number of additional records in the message.
    public let additionalRecordCount: UInt16
}

/// A label in a DNS message. This is a single part of a domain name. For example, `google` is a label in `google.com`. Labels are limited to 63 bytes and are not null terminated.
public struct DNSLabel: ExpressibleByStringLiteral {
    /// The length of the label. This is the number of bytes in the label.
    public let length: UInt8
    
    /// The bytes of the label. This is the actual label, not including the length byte. This is a maximum of 63 bytes and is not null terminated. This is the raw bytes of the label, not the UTF-8 representation.
    public let label: [UInt8]
    
    /// Creates a new label from the given string.
    public init(stringLiteral string: String) {
        self.init(bytes: Array(string.utf8))
    }
    
    /// Creates a new label from the given bytes.
    public init(bytes: [UInt8]) {
        assert(bytes.count < 64)
        
        self.label = bytes
        self.length = UInt8(bytes.count)
    }
}

/// The type of resource record. This is used to determine the format of the record.
///
/// The official standard list of all Resource Record (RR) Types. [IANA](https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml#dns-parameters-4)
public enum DNSResourceType: UInt16 {
    /// A request for an IPv4 address
    case a = 1

    /// A request for an authoritative name server
    case ns

    /// A request for a mail destination (Obsolete - see MX)
    case md

    /// A request for a mail destination (Obsolete - see MX)
    case mf

    /// A request for a canonical name for an alias.
    case cName

    /// Marks the start of a zone of authority. This is used for delegation of zones.
    case soa

    /// A request for a mail group member (Obsolete - see MX)
    case mb

    /// A request for a mail group member
    case mg

    /// A request for a mail agent (Obsolete - see MX)
    case mr

    case null

    /// A request for a well known service description. 
    case wks

    /// A domain name pointer (ie. in-addr.arpa) for address to name
    case ptr

    /// A request for a canonical name for an alias
    case hInfo

    /// A request for host information
    case mInfo

    /// A request for a mail exchange record
    case mx

    /// A request for a text record. This is used for storing arbitrary text.
    case txt

    /// A request for an IPv6 address
    case aaaa = 28

    /// A request for an SRV record. This is used for service discovery.
    case srv = 33
    
    // QuestionType exclusive

    /// A request for a transfer of an entire zone
    case axfr = 252

    /// A request for mailbox-related records (MB, MG or MR)
    case mailB = 253

    /// A request for mail agent RRs (Obsolete - see MX)
    case mailA = 254

    /// A request for all records
    case any = 255
}

public typealias QuestionType = DNSResourceType

/// The class of the resource record. This is used to determine the format of the record. 
public enum DataClass: UInt16 {
    /// The Internet
    case internet = 1

    /// The CSNET class (Obsolete - used only for examples in some obsolete RFCs)
    case chaos = 3

    /// The Hesiod class (Obsolete -
    case hesoid = 4
}

public struct QuestionSection {
    public let labels: [DNSLabel]
    public let type: QuestionType
    public let questionClass: DataClass
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
    
    /// Any other record. This is used for records that are not yet supported through convenience methods.
    case other(ResourceRecord<ByteBuffer>)
}

/// A text record. This is used for storing arbitrary text.
public struct TXTRecord: DNSResource {
    /// The values of the text record. This is a dictionary of key-value pairs.
    public let values: [String: String]
    public let rawValues: [String]
    
    init(values: [String: String], rawValues: [String]) {
        self.values = values
        self.rawValues = rawValues
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> TXTRecord? {
        var currentIndex = 0
        var components: [String: String] = [:]
        var rawValues: [String] = []
        
        while currentIndex < length {
            guard let componentLenght = buffer.readInteger(endianness: .big, as: UInt8.self) else {
                return nil
            }

            currentIndex += (Int(componentLenght) + 1)
            
            guard let componentString = buffer.readString(length: Int(componentLenght)) else {
                return nil
            }

            rawValues.append(componentString)
            
            let parts = componentString.split(separator: "=")
            
            if parts.count != 2 {
                continue
            }
            
            components[String(parts[0])] = String(parts[1])
        }
        
        return TXTRecord(values: components, rawValues: rawValues)
    }
}

/// A mail exchange record. This is used for mail servers.
public struct MXRecord: DNSResource {
    /// The preference of the mail server. This is used to determine which mail server to use.
    public let preference: Int

    /// The labels of the mail server.
    public let labels: [DNSLabel]

    public static func read(from buffer: inout ByteBuffer, length: Int) -> MXRecord? {
        guard let preference = buffer.readInteger(endianness: .big, as: UInt16.self) else { return nil }

        guard let labels = buffer.readLabels() else {
            return nil
        }

        return MXRecord(preference: Int(preference), labels: labels)
    }
}

/// A canonical name record. This is used for aliasing hostnames.
public struct CNAMERecord: DNSResource {
    /// The labels of the alias.
    public let labels: [DNSLabel]

    public static func read(from buffer: inout ByteBuffer, length: Int) -> CNAMERecord? {
        guard let labels = buffer.readLabels() else {
            return nil
        }
        return CNAMERecord(labels: labels)
    }
}

/// An IPv4 address record. This is used for resolving hostnames to IP addresses.
public struct ARecord: DNSResource {
    /// The address of the record. This is a 32-bit integer.
    public let address: UInt32

    /// The address of the record as a string.
    public var stringAddress: String {
        return withUnsafeBytes(of: address) { buffer in
            let buffer = buffer.bindMemory(to: UInt8.self)
            return "\(buffer[3]).\(buffer[2]).\(buffer[1]).\(buffer[0])"
        }
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> ARecord? {
        guard let address = buffer.readInteger(endianness: .big, as: UInt32.self) else { return nil }
        return ARecord(address: address)
    }
}

/// An IPv6 address record. This is used for resolving hostnames to IP addresses.
public struct AAAARecord: DNSResource {
    /// The address of the record. This is a 128-bit integer.
    public let address: [UInt8]

    /// The address of the record as a string.
    public var stringAddress: String {
        String(format: "%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x",
               address[0], address[1], address[2], address[3],
               address[4], address[5], address[6], address[7],
               address[8], address[9], address[10], address[11],
               address[12], address[13], address[14], address[15]
        )
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> AAAARecord? {
        guard let address = buffer.readBytes(length: 16) else { return nil }
        return AAAARecord(address: address)
    }
}

/// A structure representing a DNS resource record. This is used for storing the data of a DNS record.
public struct ResourceRecord<Resource: DNSResource> {
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
}

/// A protocol that can be used to read a DNS resource from a buffer.
public protocol DNSResource {
    static func read(from buffer: inout ByteBuffer, length: Int) -> Self?
}

/// An extension to `ByteBuffer` that adds a method for reading a DNS resource.
extension ByteBuffer: DNSResource {
    public static func read(from buffer: inout ByteBuffer, length: Int) -> ByteBuffer? {
        return buffer.readSlice(length: length)
    }
}

fileprivate struct InvalidSOARecord: Error {}

/// An extension to `ResourceRecord` that adds a method for parsing a SOA record.
extension ResourceRecord where Resource == ByteBuffer {
    mutating func parseSOA() throws -> ZoneAuthority {
        guard
            let domainName = resource.readLabels(),
            resource.readableBytes >= 20, // Minimum 5 UInt32's
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

extension UInt32 {
    /// Converts the UInt32 to a SocketAddress. This is used for converting the address of a DNS record to a SocketAddress.
    func socketAddress(port: Int) throws -> SocketAddress {
        let text = inet_ntoa(in_addr(s_addr: self.bigEndian))!
        let host = String(cString: text)
        
        return try SocketAddress(ipAddress: host, port: port)
    }
}

struct ZoneAuthority {
    let domainName: [DNSLabel]
    let adminMail: String
    let serial: UInt32
    let refreshInterval: UInt32
    let retryTimeinterval: UInt32
    let expireTimeout: UInt32
    let minimumExpireTimeout: UInt32
}

extension Sequence where Element == DNSLabel {
    /// Converts a sequence of DNS labels to a string.
    public var string: String {
        return self.compactMap { label in
            if let string = String(bytes: label.label, encoding: .utf8), string.count > 0 {
                return string
            }
            
            return nil
        }.joined(separator: ".")
    }
}

extension ByteBuffer {
    /// Either write label index or list of labels
    @discardableResult
    mutating func writeCompressedLabels(_ labels: [DNSLabel], labelIndices: inout [String: UInt16]) -> Int {
        var written = 0
        var labels = labels
        while !labels.isEmpty {
            let label = labels.removeFirst()
            // use combined labels as a key for a position in the packet
            let key = labels.string
            // if position exists output position or'ed with 0xc000 and return
            if let labelIndex = labelIndices[key] {
                written += writeInteger(labelIndex | 0xc000)
                return written
            } else {
                // if no position exists for this combination of labels output the first label
                labelIndices[key] = numericCast(writerIndex)
                written += writeInteger(UInt8(label.label.count))
                written += writeBytes(label.label)
            }
        }
        // write end of labels
        written += writeInteger(UInt8(0))
        return written
    }
    
    /// write labels into DNS packet
    @discardableResult
    mutating func writeLabels(_ labels: [DNSLabel]) -> Int {
        var written = 0
        for label in labels {
            written += writeInteger(UInt8(label.label.count))
            written += writeBytes(label.label)
        }
        
        return written
    }
    
    func labelsSize(_ labels: [DNSLabel]) -> Int {
        return labels.reduce(0, { $0 + 2 + $1.label.count })
    }
}

public struct Message {
    public internal(set) var header: DNSMessageHeader
    public let questions: [QuestionSection]
    public let answers: [Record]
    public let authorities: [Record]
    public let additionalData: [Record]
}
