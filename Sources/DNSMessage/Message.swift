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
public struct DNSMessage: Sendable {
    public var header: DNSHeader
    public var questions: [any DNSQuestionProtocol]
    public var answers: [any DNSRecordProtocol]
    public var authorities: [any DNSRecordProtocol]
    public var additionalData: [any DNSRecordProtocol]

    public init(
        header: DNSHeader,
        questions: [any DNSQuestionProtocol] = [],
        answers: [any DNSRecordProtocol] = [],
        authorities: [any DNSRecordProtocol] = [],
        additionalData: [any DNSRecordProtocol] = []
    ) {
        self.header = header
        self.questions = questions
        self.answers = answers
        self.authorities = authorities
        self.additionalData = additionalData
    }

    public func isEqual(_ other: DNSMessage) -> Bool {
        header == other.header && questions.elementsEqual(other.questions, by: { $0.isEqual($1) })
            && answers.elementsEqual(other.answers, by: { $0.isEqual($1) })
            && authorities.elementsEqual(other.authorities, by: { $0.isEqual($1) })
            && additionalData.elementsEqual(other.additionalData, by: { $0.isEqual($1) })
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

public struct DNSClientMessage: Sendable {
    public var opcode: DNSOpcode
    public var recursionDesired: Bool
    public var queries: [any DNSQuestionProtocol]

    public init(opcode: DNSOpcode = .query, recursionDesired: Bool = true, queries: [any DNSQuestionProtocol] = []) {
        self.opcode = opcode
        self.recursionDesired = recursionDesired
        self.queries = queries
    }

    package func toInternalRepresentation() throws -> DNSMessage {
        var flags: DNSHeaderFlags = []
        if self.recursionDesired {
            flags.insert(.recursionDesired)
        }

        // Convert EDNS to OPTRecord and place in additionalData
        // var additionalData: [DNSRecord] = []

        // if let edns = self.edns {
        //     additionalData.append(try edns.toInternalRepresentation())
        // }

        let header = DNSHeader(
            id: UInt16.random(in: 0...UInt16.max),
            flags: flags,
            opcode: self.opcode,
            responseCode: .noError
        )

        return DNSMessage(
            header: header,
            questions: self.queries,
            answers: [],
            authorities: [],
            // additionalData: additionalData,
            additionalData: []
            // edns: self.edns
        )
    }
}
