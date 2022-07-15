import NIO

final class EnvelopeInboundChannel: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias InboundOut = ByteBuffer
    
    init() {}
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data).data
        context.fireChannelRead(wrapInboundOut(buffer))
    }
}

final class DNSDecoder: ChannelInboundHandler {
    let group: EventLoopGroup
    var clients = [ObjectIdentifier: DNSClient]()
    var messageCache: MessageCache
    
    weak var mainClient: DNSClient?

    init(group: EventLoopGroup, client: DNSClient) {
        self.group = group
        self.mainClient = client
        self.messageCache = client.messageCache
    }

    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = Never
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        let readPromise = context.eventLoop.makePromise(of: Void.self)

        // Any failure thrown from the task passed to completeWithTask
        // will be propagated to the context
        readPromise.futureResult.whenFailure { error in
            context.fireErrorCaught(error)
        }

        readPromise.completeWithTask {
            var buffer = envelope

            guard let header = buffer.readHeader() else {
                throw ProtocolError()
            }

            var questions = [QuestionSection]()

            for _ in 0..<header.questionCount {
                guard let question = buffer.readQuestion() else {
                    throw ProtocolError()
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
                let answers = try resourceRecords(count: header.answerCount)
                let authorities = try resourceRecords(count: header.authorityCount)
                let additionalData = try resourceRecords(count: header.additionalRecordCount)

                let message = Message(
                    header: header,
                    questions: questions,
                    answers: answers,
                    authorities: authorities,
                    additionalData: additionalData
                )

                guard let query = await self.messageCache.queryForID(header.id) else {
                    throw UnknownQuery()
                }

                query.promise.succeed(message)
                await self.messageCache.removeQueryForID(header.id)
            } catch {
                await self.messageCache.queryForID(header.id)?.promise.fail(error)
                await self.messageCache.removeQueryForID(header.id)
                throw error
            }
        }
        
    }

    func errorCaught(context ctx: ChannelHandlerContext, error: Error) {
        fatalError("Unimplemented")
        // TODO: Check what to do here
        /*
        for query in self.messageCache.values {
            query.promise.fail(error)
        }

        messageCache = [:]
        */
    }
}
