public import DNSMessage
public import NIOCore

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

    func decodeLast(
        context: ChannelHandlerContext,
        buffer: inout ByteBuffer,
        seenEOF: Bool
    ) throws
        -> DecodingState
    {
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

public final class DNSClientOutboundHandler: ChannelOutboundHandler {
    public typealias OutboundIn = DNSMessage
    public typealias OutboundOut = ByteBuffer

    public func write(
        context: ChannelHandlerContext,
        data: NIOAny,
        promise: EventLoopPromise<Void>?
    ) {
        let message = unwrapOutboundIn(data)
        do {
            var encoder = DNSEncoder()
            let _ = try encoder.writeDNSMessage(message)
            context.write(wrapOutboundOut(encoder.flush()), promise: promise)
        } catch {
            context.fireErrorCaught(error)
        }
    }
}
