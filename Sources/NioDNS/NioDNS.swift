import NIO

class NioDNS {

    deinit {
        _ = channel.close(mode: .all)
    }

    let channel: Channel
    let host: String

    public static func connect(on group: EventLoopGroup, host: String) -> EventLoopFuture<NioDNS> {
        let bootstrap = ClientBootstrap(group: group)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .channelInitializer { channel in
                    return NioDNS.initialize(pipeline: channel.pipeline, hostname: host)
                }

        return bootstrap.bind(host: host, port: 53).map { channel in
            return NioDNS(channel: channel, host: host)
        }
    }

    init(channel: Channel, host: String) {
        self.channel = channel
        self.host = host
    }
    
    func sendMessage(_ message: Message) {
        _ = self.channel.writeAndFlush(message)
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

private final class DNSEncoder: MessageToByteEncoder {
    typealias OutboundIn = Message
    
    func encode(ctx: ChannelHandlerContext, data: Message, out: inout ByteBuffer) throws {
        let header = data.header
        let endianness = Endianness.big
        
        out.write(integer: header.id, endianness: endianness)
        out.write(integer: header.options.rawValue, endianness: endianness)
        out.write(integer: header.questionCount, endianness: endianness)
        out.write(integer: header.answerCount, endianness: endianness)
        out.write(integer: header.authorityCount, endianness: endianness)
        out.write(integer: header.additionalRecordCount, endianness: endianness)
        
        for question in data.questions {
            for label in question.labels {
                out.write(integer: label.length, endianness: endianness)
                out.write(bytes: label.label)
            }
            
            out.write(integer: 0, endianness: endianness, as: UInt8.self)
            out.write(integer: question.type.rawValue, endianness: endianness)
            out.write(integer: question.questionClass.rawValue, endianness: endianness)
        }
        
        print(out.getBytes(at: 0, length: out.readableBytes))
        print("break")
    }
}

private final class DNSDecoder: ByteToMessageDecoder {
    var cumulationBuffer: ByteBuffer?
    
    func decode(ctx: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        print(buffer.readBytes(length: buffer.readableBytes))
        return .continue
    }
}
