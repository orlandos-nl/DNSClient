public protocol DNSQuestionProtocol: Sendable, CustomStringConvertible, Hashable {
    var hostname: String { get }
    var type: DNSResourceType { get }
    var questionClass: DNSClass { get }

    func toInternalRepresentation() throws -> DNSQuestion
}

extension DNSQuestionProtocol {
    public var description: String {
        "\(self.hostname) \(DNSResourceType.getTypeName(for: self.type)) \(self.questionClass)"
    }

    public func isEqual(_ other: any DNSQuestionProtocol) -> Bool {
        do {
            let selfInternal = try self.toInternalRepresentation()
            let otherInternal = try other.toInternalRepresentation()
            return selfInternal == otherInternal
        } catch {
            return false
        }
    }
}

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
public struct DNSQuestion: DNSQuestionProtocol, Equatable, Sendable {
    public var name: DNSName
    public var type: DNSResourceType
    public var questionClass: DNSClass

    public var hostname: String {
        self.name.description
    }

    public init(name: DNSName, type: DNSResourceType, questionClass: DNSClass) throws {
        guard type.isValidInQuestion else {
            throw DNSMessageError.invalidQuestionType(type)
        }

        self.name = name
        self.type = type
        self.questionClass = questionClass
    }

    public func toInternalRepresentation() throws -> DNSQuestion {
        self
    }
}

public struct DNSQuery<RData: DNSResourceData>: DNSQuestionProtocol, Equatable, Sendable {
    public var hostname: String
    public var type: DNSResourceType { RData.resourceType }
    public var questionClass: DNSClass

    public init(hostname: String, class: DNSClass = .internet) {
        self.hostname = hostname
        self.questionClass = `class`
    }

    public func toInternalRepresentation() throws -> DNSQuestion {
        try DNSQuestion(
            name: try DNSName(from: self.hostname),
            type: type,
            questionClass: self.questionClass
        )
    }
}

@available(*, deprecated, renamed: "DNSQuestion")
public typealias QuestionSection = DNSQuestion

public struct DNSQueryResult<RData: DNSResourceData>: Sendable {
    public var requested: [DNSResourceRecord<RData>]
    public var message: DNSMessage

    public init(requested: [DNSResourceRecord<RData>], message: DNSMessage) {
        self.requested = requested
        self.message = message
    }
}
