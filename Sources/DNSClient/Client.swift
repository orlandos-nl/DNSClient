import NIO
import NIOConcurrencyHelpers

/// A DNS client that can be used to send queries to a DNS server.
/// The client is thread-safe and can be used from multiple threads. Supports both UDP and TCP, and multicast DNS. This client is not a full implementation of the DNS protocol, but only supports the most common queries. If you need more advanced features, you should use the `sendQuery` method to send a custom query.
/// This client is not a full resolver, and does not support caching, recursion, or other advanced features. If you need a full resolver, use the `Resolver` class.
public final class DNSClient: Resolver, Sendable {
    let dnsDecoder: DNSDecoder
    let channel: Channel
    let primaryAddress: SocketAddress
    private let isMulticastBox = NIOLockedValueBox(false)
    internal var isMulticast: Bool {
        get { isMulticastBox.withLockedValue { $0 } }
        set { isMulticastBox.withLockedValue { $0 = newValue } }
    }
    
    var loop: EventLoop {
        return channel.eventLoop
    }
    // Each query has an ID to keep track of which response belongs to which query
    let messageID: Atomic<UInt16> = Atomic(value: 0)
    
    internal init(channel: Channel, address: SocketAddress, decoder: DNSDecoder) {
        self.channel = channel
        self.primaryAddress = address
        self.dnsDecoder = decoder
    }
    
    /// Create a new `DNSClient` that will send queries to the specified address using your own `Channel`.
    public init(channel: Channel, dnsServerAddress: SocketAddress, context: DNSClientContext) {
        self.channel = channel
        self.primaryAddress = dnsServerAddress
        self.dnsDecoder = context.decoder
    }

    deinit {
        _ = channel.close(mode: .all)
    }
}

/// A context that can be used to create a `DNSClient`. This can be used to create only one `DNSClient`, but is useful if you want to use your own `Channel`.
public struct DNSClientContext {
    internal let decoder: DNSDecoder
    
    /// Create a new `DNSClientContext`. This is used to create a `DNSClient` on a custom `Channel`.
    public init(eventLoopGroup: EventLoopGroup) {
        self.decoder = DNSDecoder(group: eventLoopGroup)
    }
}

struct SentQuery {
    let message: Message
    let promise: EventLoopPromise<Message>
}
