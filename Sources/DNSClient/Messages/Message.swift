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
    case other(ResourceRecord<ByteBuffer>)
}

public struct TXTRecord: DNSResource {
    public let text: String
    public let key: String
    public let value: String
    
    init?(text: String) {
        let parts = text.split(separator: "=")
        
        if parts.count != 2 {
            return nil
        }
        
        self.text = text
        self.key = String(parts[0])
        self.value = String(parts[1])
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> TXTRecord? {
        guard let string = buffer.readString(length: length) else {
            return nil
        }
        
        return TXTRecord(text: string)
    }
}

public struct ARecord: DNSResource {
    public let address: UInt32
    public var stringAddress: String {
        return withUnsafeBytes(of: address) { buffer in
            let buffer = buffer.bindMemory(to: UInt8.self)
            return "\(buffer[0]).\(buffer[1]).\(buffer[2]).\(buffer[3])"
        }
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> ARecord? {
        guard let address = buffer.readInteger(endianness: .big, as: UInt32.self) else { return nil }
        return ARecord(address: address)
    }
}

public struct AAAARecord: DNSResource {
    public let address: [UInt8]
//    public var stringAddress: String {
//        // TODO
//    }

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

extension Array where Element == DNSLabel {
    public var string: String {
        return self.compactMap { label in
            if let string = String(bytes: label.label, encoding: .utf8), string.count > 0 {
                return string
            }
            
            return nil
            }.joined(separator: ".")
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
