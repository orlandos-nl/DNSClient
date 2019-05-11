import NIO

final class DNSEncoder: ChannelOutboundHandler {
    typealias OutboundIn = AddressedEnvelope<Message>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = self.unwrapOutboundIn(data)
        let message = data.data
        var out = ctx.channel.allocator.buffer(capacity: 512)

        let header = message.header

        out.write(header)

        for question in message.questions {
            for label in question.labels {
                out.write(integer: label.length, endianness: .big)
                out.write(bytes: label.label)
            }

            out.write(integer: 0, endianness: .big, as: UInt8.self)
            out.write(integer: question.type.rawValue, endianness: .big)
            out.write(integer: question.questionClass.rawValue, endianness: .big)
        }

        ctx.write(self.wrapOutboundOut(AddressedEnvelope(remoteAddress: data.remoteAddress, data: out)), promise: promise)
    }
}
