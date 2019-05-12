import NIO

final class DNSDecoder: ChannelInboundHandler {
    let group: EventLoopGroup
    var messageCache = [UInt16: SentQuery]()
    var clients = [ObjectIdentifier: DNSClient]()
    weak var mainClient: DNSClient?

    init(group: EventLoopGroup) {
        self.group = group
    }

    public typealias InboundIn = AddressedEnvelope<ByteBuffer>

    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        var buffer = envelope.data

        guard let header = buffer.readHeader() else {
            ctx.fireErrorCaught(ProtocolError())
            return
        }

        var questions = [QuestionSection]()

        for _ in 0..<header.questionCount {
            guard let question = buffer.readQuestion() else {
                ctx.fireErrorCaught(ProtocolError())
                return
            }

            questions.append(question)
        }

        func resourceRecords(count: UInt16) throws -> [Record] {
            var records = [Record]()

            for _ in 0..<count {
                guard let record = buffer.readRecord() else {
                    throw ProtocolError()
                }

                records.append(record)
            }

            return records
        }

        do {
            let message = Message(
                header: header,
                questions: questions,
                answers: try resourceRecords(count: header.answerCount),
                authorities: try resourceRecords(count: header.authorityCount),
                additionalData: try resourceRecords(count: header.additionalRecordCount)
            )

            guard let query = messageCache[header.id] else {
                throw UnknownQuery()
            }

            query.promise.succeed(result: message)
            messageCache[header.id] = nil
        } catch {
            messageCache[header.id]?.promise.fail(error: error)
            messageCache[header.id] = nil
            ctx.fireErrorCaught(error)
        }
    }

    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        for query in self.messageCache.values {
            query.promise.fail(error: error)
        }

        messageCache = [:]
    }
}
