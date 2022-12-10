import NIO
import Foundation

/// The header of a
public struct DNSMessageHeader {
    public internal(set) var id: UInt16
    
    public let options: MessageOptions
    
    public let questionCount: UInt16
    public let answerCount: UInt16
    public let authorityCount: UInt16
    public let additionalRecordCount: UInt16
}

public struct DNSLabel: ExpressibleByStringLiteral {
    public let length: UInt8
    
    // Max UInt8.max in length
    public let label: [UInt8]
    
    public init(stringLiteral string: String) {
        self.init(bytes: Array(string.utf8))
    }
    
    public init(bytes: [UInt8]) {
        assert(bytes.count < 64)
        
        self.label = bytes
        self.length = UInt8(bytes.count)
    }
}

public enum DNSResourceType: UInt16 {
    case a = 1
    case ns
    case md
    case mf
    case cName
    case soa
    case mb
    case mg
    case mr
    case null
    case wks
    case ptr
    case hInfo
    case mInfo
    case mx
    case txt
    case aaaa = 28
    case srv = 33
    
    // QuestionType exclusive
    case axfr = 252
    case mailB = 253
    case mailA = 254
    case any = 255
}

public typealias QuestionType = DNSResourceType

public enum DataClass: UInt16 {
    case internet = 1
    case chaos = 3
    case hesoid = 4
}

public struct QuestionSection {
    public let labels: [DNSLabel]
    public let type: QuestionType
    public let questionClass: DataClass
}

public enum Record {
    case aaaa(ResourceRecord<AAAARecord>)
    case a(ResourceRecord<ARecord>)
    case txt(ResourceRecord<TXTRecord>)
    case srv(ResourceRecord<SRVRecord>)
    case mx(ResourceRecord<MXRecord>)
    case other(ResourceRecord<ByteBuffer>)
}

public struct TXTRecord: DNSResource {
    
    public let values: [String: String]
    
    init(values: [String: String]) {
        self.values = values
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> TXTRecord? {
        var currentIndex = 0
        var components: [String: String] = [:]
        
        while currentIndex < length {
            guard let componentLenght = buffer.readInteger(endianness: .big, as: UInt8.self) else {
                return nil
            }
            
            guard let componentString = buffer.readString(length: Int(componentLenght)) else {
                return nil
            }
            
            let parts = componentString.split(separator: "=")
            
            if parts.count != 2 {
                return nil
            }
            
            components[String(parts[0])] = String(parts[1])
            currentIndex += (Int(componentLenght) + 1)
        }
        
        return TXTRecord(values: components)
    }
}

public struct MXRecord: DNSResource {
    public let preference: Int
    public let labels: [DNSLabel]

    public static func read(from buffer: inout ByteBuffer, length: Int) -> MXRecord? {
        guard let preference = buffer.readInteger(endianness: .big, as: UInt16.self) else { return nil }

        guard let labels = buffer.readLabels() else {
            return nil
        }
        return MXRecord(preference: Int(preference), labels: labels)
    }
}


public struct ARecord: DNSResource {
    public let address: UInt32
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

public struct AAAARecord: DNSResource {
    public let address: [UInt8]
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

public struct ResourceRecord<Resource: DNSResource> {
    public let domainName: [DNSLabel]
    public let dataType: UInt16
    public let dataClass: UInt16
    public let ttl: UInt32
    public var resource: Resource
}

public protocol DNSResource {
    static func read(from buffer: inout ByteBuffer, length: Int) -> Self?
}

extension ByteBuffer: DNSResource {
    public static func read(from buffer: inout ByteBuffer, length: Int) -> ByteBuffer? {
        return buffer.readSlice(length: length)
    }
}

fileprivate struct InvalidSOARecord: Error {}

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

// TODO: https://tools.ietf.org/html/rfc1035 section 4.1.4 compression

public struct Message {
    public internal(set) var header: DNSMessageHeader
    public let questions: [QuestionSection]
    public let answers: [Record]
    public let authorities: [Record]
    public let additionalData: [Record]
}
