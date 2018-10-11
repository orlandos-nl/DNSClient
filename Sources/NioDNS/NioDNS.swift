import NIO

class NioDNS {

    deinit {
        _ = channel.close(mode: .all)
    }

    let channel: Channel
    let host: String

    public static func connect(on group: EventLoopGroup, host: String) -> EventLoopFuture<NioDNS> {
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer { channel in
                return NioDNS.initialize(pipeline: channel.pipeline, hostname: host)
            }

        return bootstrap.bind(host: "0.0.0.0", port: 0).map { channel in
            return NioDNS(channel: channel, host: host)
        }
    }

    init(channel: Channel, host: String) {
        self.channel = channel
        self.host = host
    }
    
    func sendMessage(_ message: Message) {
        try! channel.writeAndFlush(AddressedEnvelope(remoteAddress: SocketAddress(ipAddress: host, port: 53), data: message), promise: nil)
    }

    static func initialize(pipeline: ChannelPipeline, hostname: String) -> EventLoopFuture<Void> {
        /*var handlers: [ChannelHandler] = []
        func addNext() {
            guard handlers.count > 0 else {
                promise.succeed(result: ())
                return
            }

            let handler = handlers.removeFirst()

            pipeline.add(handler: handler).whenSuccess {
                addNext()
            }
        }
        addNext()*/
        return pipeline.add(handler: DNSDecoder()).then {
            pipeline.add(handler: DNSEncoder())
        }
    }
}

private final class DNSEncoder: ChannelOutboundHandler {
    typealias OutboundIn = AddressedEnvelope<Message>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    
    func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = self.unwrapOutboundIn(data)
        let message = data.data
        var out = ctx.channel.allocator.buffer(capacity: 512)
        
        let header = message.header
        let endianness = Endianness.big
        
        out.write(integer: header.id, endianness: endianness)
        out.write(integer: header.options.rawValue, endianness: endianness)
        out.write(integer: header.questionCount, endianness: endianness)
        out.write(integer: header.answerCount, endianness: endianness)
        out.write(integer: header.authorityCount, endianness: endianness)
        out.write(integer: header.additionalRecordCount, endianness: endianness)
        
        for question in message.questions {
            for label in question.labels {
                out.write(integer: label.length, endianness: endianness)
                out.write(bytes: label.label)
            }
            
            out.write(integer: 0, endianness: endianness, as: UInt8.self)
            out.write(integer: question.type.rawValue, endianness: endianness)
            out.write(integer: question.questionClass.rawValue, endianness: endianness)
        }
        
        ctx.write(self.wrapOutboundOut(AddressedEnvelope(remoteAddress: data.remoteAddress, data: out)), promise: promise)
    }
}

private final class DNSDecoder: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    
    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        var buffer = envelope.data
        
        // To begin with, the chat messages are simply whole datagrams, no other length.
        guard let message = buffer.readString(length: buffer.readableBytes) else {
            print("Error: invalid string received")
            return
        }
        
        print("\(envelope.remoteAddress): \(message)")
    }
}
