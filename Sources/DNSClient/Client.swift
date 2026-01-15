import NIO
import NIOConcurrencyHelpers

/// A DNS client that can be used to send queries to a DNS server.
/// The client is thread-safe and can be used from multiple threads. Supports both UDP and TCP. This client is not a full implementation of the DNS protocol, but only supports the most common queries. If you need more advanced features, you should use the `sendQuery` method to send a custom query.
/// This client is not a full resolver, and does not support caching, recursion, or other advanced features. If you need a full resolver, use the `Resolver` class.
/// For multicast DNS (mDNS), use `MulticastDNSClient` instead.
public class DNSClient: Resolver, @unchecked Sendable {
    let dnsDecoder: DNSDecoder
    let channel: Channel
    let primaryAddress: SocketAddress
    
    var loop: EventLoop {
        return channel.eventLoop
    }
    // Each query has an ID to keep track of which response belongs to which query
    let messageID: NIOLockedValueBox<UInt16> = NIOLockedValueBox(0)
    
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

    /// Send a question to the dns host
    ///
    /// - Parameters:
    ///     - address: The hostname address to request a certain resource from
    ///     - type: The resource you want to request
    ///     - additionalOptions: Additional message options
    ///     - timeout: Timeout for this query (default: 30s to preserve existing behavior)
    /// - Returns: A future with the response message
    public func sendQuery(
        forHost address: String,
        type: DNSResourceType,
        additionalOptions: MessageOptions? = nil,
        timeout: TimeAmount = .seconds(30)
    ) -> EventLoopFuture<Message> {
        channel.eventLoop.flatSubmit {
            let messageID = self.messageID.withLockedValue { id in
                let newID = id &+ 1
                id = newID
                return id
            }

            var options: MessageOptions = [.standardQuery, .recursionDesired]

            if let additionalOptions = additionalOptions {
                options.insert(additionalOptions)
            }

            let header = DNSMessageHeader(id: messageID, options: options, questionCount: 1, answerCount: 0, authorityCount: 0, additionalRecordCount: 0)
            let labels = address.split(separator: ".").map(String.init).map(DNSLabel.init)
            let question = QuestionSection(labels: labels, type: type, questionClass: .internet)
            let message = Message(header: header, questions: [question], answers: [], authorities: [], additionalData: [])

            return self.send(message, to: nil, timeout: timeout)
        }
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

final class SentMulticastQuery: @unchecked Sendable {
    let message: Message
    let promise: EventLoopPromise<[Message]>
    private var _responses: [Message] = []
    private let lock = NIOLock()

    init(message: Message, promise: EventLoopPromise<[Message]>) {
        self.message = message
        self.promise = promise
    }

    func addResponse(_ response: Message) {
        lock.withLock {
            _responses.append(response)
        }
    }

    var responses: [Message] {
        lock.withLock { _responses }
    }
}
