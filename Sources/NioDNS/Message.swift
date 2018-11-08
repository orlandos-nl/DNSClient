fileprivate let opCodeBits: UInt16 = 0b01111000_00000000
fileprivate let resuleCodeBits: UInt16 = 0b00000000_00001111

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
    
//    Note that the contents of the answer section may have
//    multiple owner names because of aliases.
//    The AA bit corresponds to the name which matches the query name, or
//    the first owner name in the answer section.
}

public struct MessageHeader {
    public let id: UInt16

    public let options: MessageOptions

    public let questionCount: UInt16
    public let answerCount: UInt16
    public let authorityCount: UInt16
    public let additionalRecordCount: UInt16
}

public struct QuestionLabel: ExpressibleByStringLiteral {
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
    public let labels: [QuestionLabel]
    public let type: QuestionType
    public let questionClass: DataClass
}

// E.G. IPv4, IPv6, ...
public struct ResourceData {
    public var data: [UInt8]
}

public struct ResourceRecord {
    public let domainName: [QuestionLabel]
    public let dataType: ResourceType
    public let dataClass: DataClass
    public let ttl: UInt32
    public let resourceDataLength: UInt16
    public let resourceData: ResourceData
}

// TODO: https://tools.ietf.org/html/rfc1035 section 4.1.4 compression

public struct Message {
    public let header: MessageHeader
    public let questions: [QuestionSection]
    public let answers: [ResourceRecord]
    public let authorities: [ResourceRecord]
    public let additionalData: [ResourceRecord]
}
