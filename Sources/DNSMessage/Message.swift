/// The basic request and response data structure, used for all DNS protocols.
///
/// [RFC 1035, DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION, November 1987](https://tools.ietf.org/html/rfc1035)
///
/// ```text
/// 4.1. Format
///
/// All communications inside of the domain protocol are carried in a single
/// format called a message.  The top level format of message is divided
/// into 5 sections (some of which are empty in certain cases) shown below:
///
///     +--------------------------+
///     |        Header            |
///     +--------------------------+
///     |  Question / Zone         | the question for the name server
///     +--------------------------+
///     |   Answer  / Prerequisite | RRs answering the question
///     +--------------------------+
///     | Authority / Update       | RRs pointing toward an authority
///     +--------------------------+
///     |      Additional          | RRs holding additional information
///     +--------------------------+
///
/// The header section is always present.  The header includes fields that
/// specify which of the remaining sections are present, and also specify
/// whether the message is a query or a response, a standard query or some
/// other opcode, etc.
///
/// The names of the sections after the header are derived from their use in
/// standard queries.  The question section contains fields that describe a
/// question to a name server.  These fields are a query type (QTYPE), a
/// query class (QCLASS), and a query domain name (QNAME).  The last three
/// sections have the same format: a possibly empty list of concatenated
/// resource records (RRs).  The answer section contains RRs that answer the
/// question; the authority section contains RRs that point toward an
/// authoritative name server; the additional records section contains RRs
/// which relate to the query, but are not strictly answers for the
/// question.
/// ```
public struct DNSMessage {
    public var header: DNSHeader
    public var questions: [QuestionSection]
    public var answers: [Record]
    public var authorities: [Record]
    public var additionalData: [Record]

    public init(
        header: DNSHeader,
        questions: [QuestionSection] = [],
        answers: [Record] = [],
        authorities: [Record] = [],
        additionalData: [Record] = []
    ) {
        self.header = header
        self.questions = questions
        self.answers = answers
        self.authorities = authorities
        self.additionalData = additionalData
    }
}

extension DNSMessage {
    public var isResponse: Bool {
        self.header.flags.contains(.response)
    }

    public var isAuthoritativeAnswer: Bool {
        self.header.flags.contains(.authoritativeAnswer)
    }

    public var isTruncated: Bool {
        self.header.flags.contains(.truncation)
    }

    public var isRecursionDesired: Bool {
        self.header.flags.contains(.recursionDesired)
    }

    public var isRecursionAvailable: Bool {
        self.header.flags.contains(.authenticData)
    }

    public var isAuthenticData: Bool {
        self.header.flags.contains(.authenticData)
    }

    public var isCheckingDisabled: Bool {
        self.header.flags.contains(.checkingDisabled)
    }
}

@available(*, deprecated, renamed: "DNSMessage")
public typealias Message = DNSMessage
