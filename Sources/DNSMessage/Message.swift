public struct Message {
    public internal(set) var header: DNSMessageHeader
    public let questions: [QuestionSection]
    public let answers: [Record]
    public let authorities: [Record]
    public let additionalData: [Record]

    public init(
        header: DNSMessageHeader,
        questions: [QuestionSection],
        answers: [Record],
        authorities: [Record],
        additionalData: [Record]
    ) {
        self.header = header
        self.questions = questions
        self.answers = answers
        self.authorities = authorities
        self.additionalData = additionalData
    }
}
