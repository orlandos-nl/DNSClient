import NIO

final class DNSEncoder: ChannelOutboundHandler {
    typealias OutboundIn = AddressedEnvelope<Message>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    
    init() {}
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        let data = DNSEncoder.encodeMessage(message.data, allocator: context.channel.allocator)

        let envelope = AddressedEnvelope(remoteAddress: message.remoteAddress, data: data)
        context.write(wrapOutboundOut(envelope), promise: promise)
    }
    
    static func encodeMessage(_ message: Message, allocator: ByteBufferAllocator) -> ByteBuffer {
        var out = allocator.buffer(capacity: 512)

        let header = message.header

        out.write(header)

        for question in message.questions {
            for label in question.labels {
                out.writeInteger(label.length, endianness: .big)
                out.writeBytes(label.label)
            }

            out.writeInteger(0, endianness: .big, as: UInt8.self)
            out.writeInteger(question.type.rawValue, endianness: .big)
            out.writeInteger(question.questionClass.rawValue, endianness: .big)
        }

        return out
    }
}
