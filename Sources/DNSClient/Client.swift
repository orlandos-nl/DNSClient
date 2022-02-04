import Dispatch
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
    
    public init(channel: Channel, dnsServerAddress: SocketAddress, context: DNSClientContext) {
        self.channel = channel
        self.primaryAddress = dnsServerAddress
        self.dnsDecoder = context.decoder
    }

    deinit {
        // This can crash the codebase if de-inited due t a failed UDP connection
        DispatchQueue.main.async { [channel] in
            _ = channel.close(mode: .all)
        }
    }
}

public struct DNSClientContext {
    internal let decoder: DNSDecoder
    
    public init() {
        self.decoder = DNSDecoder()
    }
}

struct SentQuery {
    let message: Message
    let promise: EventLoopPromise<Message>
}
