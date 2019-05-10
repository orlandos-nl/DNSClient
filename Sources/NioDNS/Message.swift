import NIO
import Foundation

fileprivate let opCodeBits: UInt16 = 0b01111000_00000000
fileprivate let resultCodeBits: UInt16 = 0b00000000_00001111

public struct MessageOptions: OptionSet, ExpressibleByIntegerLiteral {
    public var rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    public init(integerLiteral value: UInt16) {
        self.rawValue = value
    }
    
    public static let answer: MessageOptions = 0b10000000_00000000
    public static let authorativeAnswer: MessageOptions = 0b00000100_00000000
    public static let truncated: MessageOptions = 0b00000010_00000000
    public static let recursionDesired: MessageOptions = 0b00000001_00000000
    public static let recursionAvailable: MessageOptions = 0b00000000_10000000
    
    public static let standardQuery: MessageOptions = 0b00000000_00000000
    public static let inverseQuery: MessageOptions = 0b00001000_00000000
    public static let serverStatusQuery: MessageOptions = 0b00010000_00000000
    
    public static let resultCodeSuccess: MessageOptions = 0b00000000_00000000
    public static let resultCodeFormatError: MessageOptions = 0b00000000_00000001
    public static let resultCodeServerfailure: MessageOptions = 0b00000000_00000010
    public static let resultCodeNameError: MessageOptions = 0b00000000_00000011
    public static let resultCodeNotImplemented: MessageOptions = 0b00000000_00000100
    public static let resultCodeNotRefused: MessageOptions = 0b00000000_00000101
    
    public var isAnswer: Bool {
        return self.contains(.answer)
    }
    
    public var isAuthorativeAnswer: Bool {
        return self.contains(.authorativeAnswer)
    }
    
    public var isQuestion: Bool {
        return !isAnswer
    }
    
    public var isStandardQuery: Bool {
        return rawValue & opCodeBits == MessageOptions.standardQuery.rawValue
    }
    
    public var isInverseQuery: Bool {
        return rawValue & opCodeBits == MessageOptions.inverseQuery.rawValue
    }
    
    public var isServerStatusQuery: Bool {
        return rawValue & opCodeBits == MessageOptions.serverStatusQuery.rawValue
    }
    
    public var isSuccessful: Bool {
        return self.contains(.resultCodeSuccess)
    }
    
    public var isFormatError: Bool {
        return self.contains(.resultCodeFormatError)
    }
    
    public var isServerFailure: Bool {
        return self.contains(.resultCodeServerfailure)
    }
    
    public var isNameError: Bool {
        return self.contains(.resultCodeNameError)
    }
    
    public var isNotImplemented: Bool {
        return self.contains(.resultCodeNotImplemented)
    }
    
    public var isNotRefused: Bool {
        return self.contains(.resultCodeNotRefused)
    }
    
    public var isRefused: Bool {
        return !isNotRefused
    }
    
    //    Note that the contents of the answer section may have
    //    multiple owner names because of aliases.
    //    The AA bit corresponds to the name which matches the query name, or
    //    the first owner name in the answer section.
}

public struct MessageHeader {
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

public enum ResourceType: UInt16 {
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

public typealias QuestionType = ResourceType

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

    public static func read(from buffer: inout ByteBuffer, length: Int) -> TXTRecord? {
        guard let labels = buffer.readLabels() else { return nil }
        return TXTRecord(text: labels.string)
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
        let text = inet_ntoa(in_addr(s_addr: self))!
        let host = String(cString: text)
        
        return try SocketAddress(ipAddress: host, port: UInt16(port))
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
    public internal(set) var header: MessageHeader
    public let questions: [QuestionSection]
    public let answers: [Record]
    public let authorities: [Record]
    public let additionalData: [Record]
}
