import DNSMessage
import NIOConcurrencyHelpers
public import NIOCore

final class EnvelopeInboundChannel: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias InboundOut = ByteBuffer

    init() {}

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data).data
        context.fireChannelRead(wrapInboundOut(buffer))
    }
}

public final class DNSClientInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    let group: EventLoopGroup
    let messageCache = NIOLockedValueBox<[UInt16: SentQuery]>([:])
    let clients = NIOLockedValueBox<[ObjectIdentifier: DNSClient]>([:])
    weak var mainClient: DNSClient?

    public init(group: EventLoopGroup) {
        self.group = group
    }

    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = Never

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message: DNSMessage
        var decoder = DNSDecoder(buffer: unwrapInboundIn(data))

        do {
            message = try decoder.readDNSMessage()
        } catch {
            context.fireErrorCaught(error)
            return
        }

        if !message.isResponse {
            return
        }

        messageCache.withLockedValue { cache in
            guard let query = cache[message.header.id] else {
                return
            }

            query.promise.succeed(message)
            cache[message.header.id] = nil
        }
    }

    public func errorCaught(context ctx: ChannelHandlerContext, error: Error) {
        messageCache.withLockedValue { cache in
            for query in cache.values {
                query.promise.fail(error)
            }

            cache = [:]
        }
    }
}
