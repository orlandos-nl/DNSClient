/// Represents the 12-byte header of a DNS message.
///
/// The header contains a unique identifier, flags, and counts for the
/// number of records in each subsequent section of the message.
///
/// ### Header Format
/// ```
///                                     1  1  1  1  1  1
///       0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                      ID                       |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |QR|   Opcode  |AA|TC|RD|RA| Z|AD|CD|   RCODE   |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                    QDCOUNT                    |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                    ANCOUNT                    |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                    NSCOUNT                    |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     |                    ARCOUNT                    |
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// ```
/// - Note: `AD` and `CD` flags are defined in [RFC4035](https://datatracker.ietf.org/doc/html/rfc4035).
///         The other fields are defined in [RFC1035](https://datatracker.ietf.org/doc/html/rfc1035).
public struct DNSHeader: Sendable {
    public var id: UInt16
    public var flags: DNSHeaderFlags
    public var opcode: DNSOpcode
    public var responseCode: DNSResponseCode

    internal var questionCount: UInt16 = 0
    internal var answerCount: UInt16 = 0
    internal var authorityCount: UInt16 = 0
    internal var additionalDataCount: UInt16 = 0

    public init(
        id: UInt16,
        flags: DNSHeaderFlags,
        opcode: DNSOpcode = .query,
        responseCode: DNSResponseCode = .noError
    ) {
        self.id = id
        self.flags = flags
        self.opcode = opcode
        self.responseCode = responseCode
    }

    internal init(
        id: UInt16,
        flags: DNSHeaderFlags,
        opcode: DNSOpcode,
        responseCode: DNSResponseCode,
        questionCount: UInt16,
        answerCount: UInt16,
        authorityCount: UInt16,
        additionalDataCount: UInt16,
    ) {
        self.id = id
        self.flags = flags
        self.opcode = opcode
        self.responseCode = responseCode
        self.questionCount = questionCount
        self.answerCount = answerCount
        self.authorityCount = authorityCount
        self.additionalDataCount = additionalDataCount
    }
}

/// `DNSMessageHeader` has been deprecated in favor of the new `DNSHeader` architecture.
///
/// ## Reasons for Deprecation
/// The original `DNSMessageHeader` stored all header information in a single `options` field,
/// which had several limitations:
///
/// 1. **Separation of Concerns**: Mixed flags, opcodes, and response codes in one field
/// 2. **EDNS Support**: Could not properly handle EDNS(0) extended response codes (12-bit vs 4-bit)
/// 3. **Protocol Validity**: Made it possible to create invalid DNS message combinations
/// 4. **Count Fields**: Count fields are now accessed from the DNSMessage type and automatically managed during encoding
///
/// ## Migration Path
/// The new `DNSHeader` separates these concerns into distinct fields:
/// - `flags: DNSHeaderFlags` for header flags (QR, AA, TC, RD, RA, AD, CD)
/// - `opcode: DNSOpcode` for operation codes (QUERY, STATUS, NOTIFY, UPDATE, DSO)
/// - `responseCode: DNSResponseCode` for response codes with proper EDNS support
/// - Count fields are now internal and automatically managed by the encoder
///
/// ### Before (deprecated):
/// ```swift
/// let header = DNSMessageHeader(
///     id: 12345,
///     options: [.answer, .authoritativeAnswer, .standardQuery],
///     questionCount: 1,
///     answerCount: 2,
///     authorityCount: 0,
///     additionalRecordCount: 1
/// )
/// let questionCount = header.questionCount
/// ```
///
/// ### After (recommended):
/// ```swift
/// let header = DNSHeader(
///     id: 12345,
///     flags: [.response, .authoritativeAnswer],
///     opcode: .query,
///     responseCode: .NoError
/// )
/// // Access counts directly from the message
/// let questionCount = message.questions.count
/// let additionalDataCount = message.additionalData.count
/// ```
@available(
    *,
    deprecated,
    message: """
        DNSMessageHeader has been replaced with DNSHeader for better separation of concerns and EDNS support.

        Migration guide:
        - Use separate 'flags', 'opcode', and 'responseCode' fields instead of combined 'options'
        - Access counts directly from the Message: message.questions.count, message.additionalData.count, etc.
        - Access flags via header.flags, opcodes via header.opcode, response codes via header.responseCode
        """
)
public typealias DNSMessageHeader = DNSHeader
