public struct QuestionSection {
    public let labels: [DNSLabel]
    public let type: QuestionType
    public let questionClass: DataClass

    public init(labels: [DNSLabel], type: QuestionType, questionClass: DataClass) {
        self.labels = labels
        self.type = type
        self.questionClass = questionClass
    }
}
