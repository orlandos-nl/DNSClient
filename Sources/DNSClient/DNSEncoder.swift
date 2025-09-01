import DNSMessage
import NIO

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

final class UInt16FrameDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        var readBuffer = buffer
        guard
            let size: UInt16 = readBuffer.readInteger(),
            let slice = readBuffer.readSlice(length: Int(size))
        else {
            return .needMoreData
        }

        buffer.moveReaderIndex(to: readBuffer.readerIndex)
        context.fireChannelRead(wrapInboundOut(slice))
        return .continue
    }

    func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        try decode(context: context, buffer: &buffer)
    }
}

final class UInt16FrameEncoder: MessageToByteEncoder {
    func encode(data: ByteBuffer, out: inout ByteBuffer) throws {
        try out.writeLengthPrefixed(as: UInt16.self) { out in
            out.writeImmutableBuffer(data)
        }
    }
}

public final class DNSEncoder: ChannelOutboundHandler {
    public typealias OutboundIn = Message
    public typealias OutboundOut = ByteBuffer

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        do {
            var labelIndices = [String: UInt16]()
            let data = try DNSEncoder.encodeMessage(
                message,
                allocator: context.channel.allocator,
                labelIndices: &labelIndices
            )

            context.write(wrapOutboundOut(data), promise: promise)
        } catch {
            context.fireErrorCaught(error)
        }
    }

    public static func encodeMessage(
        _ message: Message,
        allocator: ByteBufferAllocator,
        labelIndices: inout [String: UInt16]
    ) throws -> ByteBuffer {
        var out = allocator.buffer(capacity: 512)

        let header = message.header

        out.write(header)

        for question in message.questions {
            out.writeCompressedLabels(question.labels, labelIndices: &labelIndices)

            out.writeInteger(question.type.rawValue, endianness: .big)
            out.writeInteger(question.questionClass.rawValue, endianness: .big)
        }

        for answer in message.answers {
            try out.writeAnyRecord(answer, labelIndices: &labelIndices)
        }

        for authority in message.authorities {
            try out.writeAnyRecord(authority, labelIndices: &labelIndices)
        }

        for additionalData in message.additionalData {
            try out.writeAnyRecord(additionalData, labelIndices: &labelIndices)
        }

        return out
    }
}
