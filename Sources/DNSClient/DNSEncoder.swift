import NIO
import DNSProtocol

final class EnvelopeOutboundChannel: ChannelOutboundHandler {
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    let address: SocketAddress

    init(address: SocketAddress) {
        self.address = address
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        let envelope = AddressedEnvelope(remoteAddress: address, data: buffer)
        context.write(wrapOutboundOut(envelope), promise: promise)
    }
}

public final class DNSEncoder: ChannelOutboundHandler {
    public typealias OutboundIn = Message
    public typealias OutboundOut = ByteBuffer

    public init() {}

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        do {
            var labelIndices = [String: UInt16]()
            let data = try DNSMessageEncoder.encodeMessage(
                message,
                allocator: context.channel.allocator,
                labelIndices: &labelIndices
            )

            context.write(wrapOutboundOut(data), promise: promise)
        } catch {
            context.fireErrorCaught(error)
        }
    }
}
