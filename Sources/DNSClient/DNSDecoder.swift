import NIO
import NIOConcurrencyHelpers

public final class DNSDecoder: ChannelInboundHandler, @unchecked Sendable {
    let group: EventLoopGroup
    let messageCache = NIOLockedValueBox<[UInt16: SentQuery]>([:])
    let clients = NIOLockedValueBox<[ObjectIdentifier: DNSClient]>([:])
    let handleMulticast = NIOLockedValueBox<DNSClient.HandleMulticastMessage>({ _ in
        return nil
    })
    weak var mainClient: DNSClient?

    public init(group: EventLoopGroup) {
        self.group = group
    }

    public typealias InboundIn = AddressedEnvelope<ByteBuffer>

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let message: Message

        do {
            message = try Self.parse(envelope.data)
        } catch {
            context.fireErrorCaught(error)
            return
        }

        if message.header.options.contains(.answer) {
            return messageCache.withLockedValue { cache in
                guard let query = cache[message.header.id] else {
                    return
                }

                query.continuation.yield(message)
                cache[message.header.id] = nil
                return
            }
        }

        let callback = handleMulticast.withLockedValue(\.self)
        Task { [channel = context.channel] in
            if let reply = try await callback(message) {
                try await channel.writeAndFlush(reply)
            }
        }
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
        messageCache.withLockedValue { cache in
            for query in cache.values {
                query.continuation.finish(throwing: error)
            }

            cache = [:]
        }
    }
}
