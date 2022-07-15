import NIO

public final class DNSClient: Resolver {
    var messageCache = MessageCache()
    let channelWrapper: GuaranteedAsyncValue<Channel, DNSClient>
    var channel: Channel {
        get async throws {
            return try await channelWrapper.getValue(context: self)
        }
    }
    let primaryAddress: SocketAddress
    let loop: EventLoop
    // Each query has an ID to keep track of which response belongs to which query
    var messageID: UInt16 = 0
    
    internal init(channelWrapper: GuaranteedAsyncValue<Channel, DNSClient>, address: SocketAddress, eventLoop: EventLoop) {
        self.channelWrapper = channelWrapper
        self.primaryAddress = address
        self.loop = eventLoop
    }
    
    public init(channel: Channel, dnsServerAddress: SocketAddress, context: DNSClientContext) {
        self.channelWrapper = GuaranteedAsyncValue<Channel, DNSClient>(generator: { _ in channel }, precondition: { _, _ in true })
        self.primaryAddress = dnsServerAddress
        self.loop = channel.eventLoop
    }

    deinit {
        Task {
            _ = try await channel.close(mode: .all)
        }
    }
}

public struct DNSClientContext {
    // internal let decoder: DNSDecoder
    
    public init(eventLoopGroup: EventLoopGroup) {
        /*
        self.decoder = DNSDecoder(group: eventLoopGroup)
        */
    }
}

struct SentQuery {
    let message: Message
    let promise: EventLoopPromise<Message>
}
