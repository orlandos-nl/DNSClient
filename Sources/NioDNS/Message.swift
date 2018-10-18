fileprivate let opCodeBits: UInt16 = 0b01111000_00000000
fileprivate let resuleCodeBits: UInt16 = 0b00000000_00001111

struct MessageOptions: OptionSet, ExpressibleByIntegerLiteral {
    var rawValue: UInt16
    
    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    init(integerLiteral value: UInt16) {
        self.rawValue = value
    }
    
    static let answer: MessageOptions = 0b10000000_00000000
    static let authorativeAnswer: MessageOptions = 0b00000100_00000000
    static let truncated: MessageOptions = 0b00000010_00000000
    static let recursionDesired: MessageOptions = 0b00000001_00000000
    static let recursionAvailable: MessageOptions = 0b00000000_10000000
    
    static let standardQuery: MessageOptions = 0b00000000_00000000
    static let inverseQuery: MessageOptions = 0b00001000_00000000
    static let serverStatusQuery: MessageOptions = 0b00010000_00000000
    
    static let resultCodeSuccess: MessageOptions = 0b00000000_00000000
    static let resultCodeFormatError: MessageOptions = 0b00000000_00000001
    static let resultCodeServerfailure: MessageOptions = 0b00000000_00000010
    static let resultCodeNameError: MessageOptions = 0b00000000_00000011
    static let resultCodeNotImplemented: MessageOptions = 0b00000000_00000100
    static let resultCodeNotRefused: MessageOptions = 0b00000000_00000101
    
    var isAnswer: Bool {
        return self.contains(.answer)
    }
    
    var isQuestion: Bool {
        return !isAnswer
    }
    
    var isStandardQuery: Bool {
        return rawValue & opCodeBits == MessageOptions.standardQuery.rawValue
    }
    
    var isInverseQuery: Bool {
        return rawValue & opCodeBits == MessageOptions.inverseQuery.rawValue
    }
    
    var isServerStatusQuery: Bool {
        return rawValue & opCodeBits == MessageOptions.serverStatusQuery.rawValue
    }
    
//    Note that the contents of the answer section may have
//    multiple owner names because of aliases.
//    The AA bit corresponds to the name which matches the query name, or
//    the first owner name in the answer section.
//    var isAuthorativeAnswer: Bool {
//        return isAnswer &&
//    }
}

struct MessageHeader {
    let id: UInt16
    
    let options: MessageOptions
    
    let questionCount: UInt16
    let answerCount: UInt16
    let authorityCount: UInt16
    let additionalRecordCount: UInt16
}

struct QuestionLabel: ExpressibleByStringLiteral {
    let length: UInt8
    
    // Max UInt8.max in length
    let label: [UInt8]
    
    init(stringLiteral string: String) {
        self.init(bytes: Array(string.utf8))
    }
    
    init(bytes: [UInt8]) {
        assert(bytes.count < 64)
        
        self.label = bytes
        self.length = UInt8(bytes.count)
    }
}

enum ResourceType: UInt16 {
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
    case srv = 33

    // QuestionType exclusive
    case axfr = 252
    case mailB = 253
    case mailA = 254
    case any = 255
}

typealias QuestionType = ResourceType

enum DataClass: UInt16 {
    case internet = 1
    case chaos = 3
    case hesoid = 4
}

struct QuestionSection {
    let labels: [QuestionLabel]
    let type: QuestionType
    let questionClass: DataClass
}

// E.G. IPv4, IPv6, ...
struct ResourceData {
    var data: [UInt8]
}

struct ResourceRecord {
    let domainName: [QuestionLabel]
    let dataType: ResourceType
    let dataClass: DataClass
    let ttl: UInt32
    let resourceDataLength: UInt16
    let resourceData: ResourceData
}

// TODO: https://tools.ietf.org/html/rfc1035 section 4.1.4 compression

struct Message {
    let header: MessageHeader
    let questions: [QuestionSection]
    let answers: [ResourceRecord]
    let authorities: [ResourceRecord]
    let additionalData: [ResourceRecord]
}
