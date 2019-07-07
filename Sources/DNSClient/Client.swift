import NIO

public final class DNSClient: Resolver {
    let dnsDecoder: DNSDecoder
    let channel: Channel
    let primaryAddress: SocketAddress
    var loop: EventLoop {
        return channel.eventLoop
    }
    // Each query has an ID to keep track of which response belongs to which query
    var messageID: UInt16 = 0
    
    internal init(channel: Channel, address: SocketAddress, decoder: DNSDecoder) {
        self.channel = channel
        self.primaryAddress = address
        self.dnsDecoder = decoder
    }

    deinit {
        _ = channel.close(mode: .all)
    }
}

struct SentQuery {
    let message: Message
    let promise: EventLoopPromise<Message>
}
