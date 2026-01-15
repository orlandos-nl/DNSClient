import NIO
import NIOConcurrencyHelpers
import DNSProtocol

final class EnvelopeInboundChannel: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias InboundOut = ByteBuffer

    init() {}

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data).data
        context.fireChannelRead(wrapInboundOut(buffer))
    }
}

public final class DNSDecoder: ChannelInboundHandler, @unchecked Sendable {
    let group: EventLoopGroup
    let messageCache = NIOLockedValueBox<[UInt16: SentQuery]>([:])
    let multicastCache = NIOLockedValueBox<[UInt16: SentMulticastQuery]>([:])
    let clients = NIOLockedValueBox<[ObjectIdentifier: DNSClient]>([:])
    weak var mainClient: DNSClient?

    public init(group: EventLoopGroup) {
        self.group = group
    }

    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = Never

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message: Message

        do {
            message = try DNSMessageDecoder.parse(unwrapInboundIn(data))
        } catch {
            context.fireErrorCaught(error)
            return
        }

        if !message.header.options.contains(.answer) {
            return
        }

        // Check multicast cache first - accumulate responses
        let handledByMulticast = multicastCache.withLockedValue { cache -> Bool in
            guard let query = cache[message.header.id] else {
                return false
            }
            query.addResponse(message)
            return true
        }

        if handledByMulticast {
            return
        }

        // Regular unicast query - complete on first response
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
