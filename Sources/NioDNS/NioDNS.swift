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

        return bootstrap.connect(host: host, port: 53).map { channel in
            return NioDNS(channel: channel, host: host)
        }
    }

    init(channel: Channel, host: String) {
        self.channel = channel
        self.host = host
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
        let promise: EventLoopPromise<Void> = pipeline.eventLoop.newPromise()
        pipeline.add(handler: EchoHandler())
        return promise.futureResult
    }
}

private final class EchoHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let addressedEnvelope = self.unwrapInboundIn(data)
        print("Recieved data from \(addressedEnvelope.remoteAddress)")
        ctx.write(data, promise: nil)
    }

    public func channelReadComplete(ctx: ChannelHandlerContext) {
        ctx.flush()
    }

    public func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        print("error :", error)

        ctx.close(promise: nil)
    }
}
