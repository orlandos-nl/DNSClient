fileprivate let opCodeBits: UInt16 = 0b01111000_00000000
fileprivate let resultCodeBits: UInt16 = 0b00000000_00001111

/// The options for a DNS message. These are used to specify the type of query, whether the message is an answer, and the result code.
public struct MessageOptions: OptionSet, ExpressibleByIntegerLiteral, Sendable {
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
    
    public static let multicastResponse: MessageOptions = 0b10000000_00000000
    public static let mutlicastUnauthenticatedDataAcceptable: MessageOptions = 0b00000000_00010000

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
