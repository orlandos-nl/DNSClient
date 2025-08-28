/// The header of a DNS message.
public struct DNSMessageHeader {
    /// The ID of the message. This is used to match responses to requests.
    public internal(set) var id: UInt16

    /// The flags of the message.
    public let options: MessageOptions

    /// The number of questions in the message.
    public let questionCount: UInt16

    /// The number of answers in the message.
    public let answerCount: UInt16

    /// The number of authorities in the message.
    public let authorityCount: UInt16

    /// The number of additional records in the message.
    public let additionalRecordCount: UInt16

    public init(
        id: UInt16,
        options: MessageOptions,
        questionCount: UInt16,
        answerCount: UInt16,
        authorityCount: UInt16,
        additionalRecordCount: UInt16
    ) {
        self.id = id
        self.options = options
        self.questionCount = questionCount
        self.answerCount = answerCount
        self.authorityCount = authorityCount
        self.additionalRecordCount = additionalRecordCount
    }
}
