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

public final class DNSDecoder: ChannelInboundHandler {
    let group: EventLoopGroup
    var messageCache = [UInt16: SentQuery]()
    var clients = [ObjectIdentifier: DNSClient]()
    weak var mainClient: DNSClient?

    public init(group: EventLoopGroup) {
        self.group = group
    }

    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = Never
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message: Message

        do {
            message = try Self.parse(unwrapInboundIn(data))
        } catch {
            context.fireErrorCaught(error)
            return
        }

        if !message.header.options.contains(.answer) {
            return
        }

        guard let query = messageCache[message.header.id] else {
            return
        }

        query.promise.succeed(message)
        messageCache[message.header.id] = nil
    }

    public static func parse(_ buffer: ByteBuffer) throws -> Message {
        var buffer = buffer

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

        let answers = try resourceRecords(count: header.answerCount)
        let authorities = try resourceRecords(count: header.authorityCount)
        let additionalData = try resourceRecords(count: header.additionalRecordCount)

        return Message(
            header: header,
            questions: questions,
            answers: answers,
            authorities: authorities,
            additionalData: additionalData
        )
    }

    public func errorCaught(context ctx: ChannelHandlerContext, error: Error) {
        for query in self.messageCache.values {
            query.promise.fail(error)
        }

        messageCache = [:]
    }
}
