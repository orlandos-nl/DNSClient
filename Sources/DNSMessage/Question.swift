/// Represents a DNS question section entry
///
/// ### Question Format
/// ```
///                                     1  1  1  1  1  1
///       0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                     QNAME                     /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                     QTYPE                     |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                     QCLASS                    |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// ```
public struct DNSQuestion: Equatable, Sendable, Hashable {
    public let name: DNSName
    public let type: DNSResourceType
    public let questionClass: DNSClass

    public init(name: DNSName, type: DNSResourceType, questionClass: DNSClass) throws {
        guard type.isValidInQuestion else {
            throw DNSMessageError.invalidQuestionType(type)
        }

        self.name = name
        self.type = type
        self.questionClass = questionClass
    }
}

@available(*, deprecated, renamed: "DNSQuestion")
public typealias QuestionSection = DNSQuestion
