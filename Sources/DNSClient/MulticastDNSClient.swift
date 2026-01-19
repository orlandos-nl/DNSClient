import NIO
import NIOConcurrencyHelpers


/// A DNS client specialized for multicast DNS (mDNS) operations.
/// Unlike regular DNS, multicast DNS allows discovering services and devices on a local network
/// by sending queries to a multicast group where multiple devices may respond.
public final class MulticastDNSClient: DNSClient, @unchecked Sendable {

    /// Connect to the multicast DNS group and return a future with the client.
    /// - Parameters:
    ///   - group: EventLoops to use
    ///   - config: DNS multicast addresses to connect to
    /// - Returns: Future with the MulticastDNSClient
    internal static func connect(on group: EventLoopGroup, config: [SocketAddress]) -> EventLoopFuture<MulticastDNSClient> {
        guard let address = config.first else {
            return group.next().makeFailedFuture(MissingNameservers())
        }

        let dnsDecoder = DNSDecoder(group: group)

        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            #if !os(Windows)
            .channelOption(.socketOption(.so_reuseport), value: 1)
            #endif
            .channelInitializer { channel in
                return channel.pipeline.addHandlers(
                    EnvelopeInboundChannel(),
                    dnsDecoder,
                    EnvelopeOutboundChannel(address: address),
                    DNSEncoder()
                )
            }

        let ipv4 = address.protocol == .inet

        return bootstrap.bind(host: ipv4 ? "0.0.0.0" : "::", port: 0).map { channel in
            let client = MulticastDNSClient(
                channel: channel,
                address: address,
                decoder: dnsDecoder
            )

            dnsDecoder.mainClient = client
            return client
        }
    }

    /// Send a multicast DNS query and collect responses over a time period.
    ///
    /// Unlike regular DNS queries that return the first response, this method
    /// collects all responses received within the specified timeout period.
    /// This is useful for mDNS where multiple devices may respond to the same query.
    ///
    /// - Parameters:
    ///     - address: The hostname address to request a certain resource from
    ///     - type: The resource you want to request
    ///     - additionalOptions: Additional message options
    ///     - timeout: Time to wait and collect responses (default: 5 seconds)
    /// - Returns: A future with all response messages received within the timeout
    public func sendMulticastQuery(
        forHost address: String,
        type: DNSResourceType,
        additionalOptions: MessageOptions? = nil,
        timeout: TimeAmount = .seconds(5)
    ) -> EventLoopFuture<[Message]> {
        channel.eventLoop.flatSubmit {
            let messageID = self.messageID.withLockedValue { id in
                let newID = id &+ 1
                id = newID
                return id
            }

            var options: MessageOptions = [.standardQuery]

            if let additionalOptions = additionalOptions {
                options.insert(additionalOptions)
            }

            let header = DNSMessageHeader(id: messageID, options: options, questionCount: 1, answerCount: 0, authorityCount: 0, additionalRecordCount: 0)
            let labels = address.split(separator: ".").map(String.init).map(DNSLabel.init)
            let question = QuestionSection(labels: labels, type: type, questionClass: .internet)
            let message = Message(header: header, questions: [question], answers: [], authorities: [], additionalData: [])

            return self.sendMulticast(message, timeout: timeout)
        }
    }

    /// Send a multicast message and collect all responses within the timeout period.
    ///
    /// - Parameters:
    ///   - message: The DNS message to send
    ///   - timeout: Time to wait and collect responses
    /// - Returns: A future with all collected response messages
    func sendMulticast(_ message: Message, timeout: TimeAmount) -> EventLoopFuture<[Message]> {
        let promise: EventLoopPromise<[Message]> = loop.makePromise()

        return loop.flatSubmit {
            let query = SentMulticastQuery(message: message, promise: promise)

            // Register in multicast cache
            self.dnsDecoder.multicastCache.withLockedValue { cache in
                cache[message.header.id] = query
            }

            // Write on the channel
            self.channel.writeAndFlush(message, promise: nil)

            // Schedule completion after timeout - succeeds with collected responses
            self.loop.scheduleTask(in: timeout) { [multicastCache = self.dnsDecoder.multicastCache] in
                multicastCache.withLockedValue { cache in
                    cache[message.header.id] = nil
                }
                promise.succeed(query.responses)
            }

            return promise.futureResult
        }
    }

    /// Send a question to the dns host. For multicast DNS, recursion is not requested.
    ///
    /// - Parameters:
    ///     - address: The hostname address to request a certain resource from
    ///     - type: The resource you want to request
    ///     - additionalOptions: Additional message options
    ///     - timeout: Timeout for this query (default: 30s to preserve existing behavior)
    /// - Returns: A future with the response message
    public override func sendQuery(
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

            // For multicast DNS, don't request recursion
            var options: MessageOptions = [.standardQuery]

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
