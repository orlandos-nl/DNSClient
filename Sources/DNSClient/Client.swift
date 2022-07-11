import NIO

public final class DNSClient: Resolver {
    public enum ConnectionType {
        case tcp, udp
    }
    
    let dnsDecoder: DNSDecoder
    let channel: Channel
    let connectionType: ConnectionType
    let primaryAddress: SocketAddress
    var loop: EventLoop {
        return channel.eventLoop
    }
    // Each query has an ID to keep track of which response belongs to which query
    var messageID: UInt16 = 0
    
    internal init(channel: Channel, address: SocketAddress, decoder: DNSDecoder, connectionType: ConnectionType) {
        self.channel = channel
        self.primaryAddress = address
        self.dnsDecoder = decoder
        self.connectionType = connectionType
    }
    
    public init(channel: Channel, dnsServerAddress: SocketAddress, context: DNSClientContext, connectionType: ConnectionType = .udp) {
        self.channel = channel
        self.primaryAddress = dnsServerAddress
        self.dnsDecoder = context.decoder
        self.connectionType = connectionType
    }

    deinit {
        _ = channel.close(mode: .all)
    }
}

public struct DNSClientContext {
    internal let decoder: DNSDecoder
    
    public init(eventLoopGroup: EventLoopGroup) {
        self.decoder = DNSDecoder(group: eventLoopGroup)
    }
}

struct SentQuery {
    let message: Message
    let promise: EventLoopPromise<Message>
}
