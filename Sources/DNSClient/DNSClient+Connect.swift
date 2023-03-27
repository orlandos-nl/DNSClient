import NIO
import Foundation

extension DNSClient {
    /// Connect to the dns server
    ///
    /// - parameters:
    ///     - group: EventLoops to use
    /// - returns: Future with the NioDNS client
    public static func connect(on group: EventLoopGroup) -> EventLoopFuture<DNSClient> {
        do {
            let configString = try String(contentsOfFile: "/etc/resolv.conf")
            let config = try ResolvConf(from: configString)

            return connect(on: group, config: config.nameservers)
        } catch {
            return group.next().makeFailedFuture(UnableToParseConfig())
        }
    }

    /// Connect to the dns server
    ///
    /// - parameters:
    ///     - group: EventLoops to use
    ///     - host: DNS host to connect to
    /// - returns: Future with the NioDNS client
    public static func connect(on group: EventLoopGroup, host: String) -> EventLoopFuture<DNSClient> {
        do {
            let address = try SocketAddress(ipAddress: host, port: 53)
            return connect(on: group, config: [address])
        } catch {
            return group.next().makeFailedFuture(error)
        }
    }
    
    /// Creates a multicast DNS client. This client will join the multicast group and listen for responses. It will also send queries to the multicast group.
    /// - parameters:
    ///    - group: EventLoops to use
    public static func connectMulticast(on group: EventLoopGroup) -> EventLoopFuture<DNSClient> {
        do {
            let address = try SocketAddress(ipAddress: "224.0.0.251", port: 5353)
            
            return connect(on: group, config: [address]).flatMap { client in
                let channel = client.channel as! MulticastChannel
                client.isMulticast = true
                return channel.joinGroup(address).map { client }
            }
        } catch {
            return group.next().makeFailedFuture(UnableToParseConfig())
        }
    }
    
    /// Connect to the dns server using TCP
    ///
    /// - parameters:
    ///     - group: EventLoops to use
    /// - returns: Future with the NioDNS client
    public static func connectTCP(on group: EventLoopGroup) -> EventLoopFuture<DNSClient> {
        do {
            let configString = try String(contentsOfFile: "/etc/resolv.conf")
            let config = try ResolvConf(from: configString)
            
            return connectTCP(on: group, config: config.nameservers)
        } catch {
            return group.next().makeFailedFuture(UnableToParseConfig())
        }
    }
    
    /// Connect to the dns server using TCP
    ///
    /// - parameters:
    ///     - group: EventLoops to use
    ///     - host: DNS host to connect to
    /// - returns: Future with the NioDNS client
    public static func connectTCP(on group: EventLoopGroup, host: String) -> EventLoopFuture<DNSClient> {
        do {
            let address = try SocketAddress(ipAddress: host, port: 53)
            return connectTCP(on: group, config: [address])
        } catch {
            return group.next().makeFailedFuture(error)
        }
    }
    
    /// Set up the UDP channel to use the DNS protocol.
    /// - Parameters:
    ///   - channel: The UDP channel to use.
    ///   - context: A context containing the decoder and encoder to use.
    ///   - remoteAddress: The address to send the DNS requests to - based on NIO's AddressedEnvelope.
    /// - Returns: A future that will be completed when the channel is ready to use.
    public static func initializeChannel(_ channel: Channel, context: DNSClientContext, asEnvelopeTo remoteAddress: SocketAddress? = nil) -> EventLoopFuture<Void> {
        if let remoteAddress = remoteAddress {
            return channel.pipeline.addHandlers(
                EnvelopeInboundChannel(),
                context.decoder,
                EnvelopeOutboundChannel(address: remoteAddress),
                DNSEncoder()
            )
        } else {
            return channel.pipeline.addHandlers(context.decoder, DNSEncoder())
        }
    }

    /// Connect to the dns server and return a future with the client. This method will use UDP.
    /// - parameters:
    ///   - group: EventLoops to use
    ///  - config: DNS servers to connect to
    /// - returns: Future with the NioDNS client
    public static func connect(on group: EventLoopGroup, config: [SocketAddress]) -> EventLoopFuture<DNSClient> {
        guard let address = config.preferred else {
            return group.next().makeFailedFuture(MissingNameservers())
        }

        let dnsDecoder = DNSDecoder(group: group)

        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.addHandlers(
                    EnvelopeInboundChannel(),
                    dnsDecoder,
                    EnvelopeOutboundChannel(address: address),
                    DNSEncoder()
                )
        }

		let ipv4 = address.protocol.rawValue == PF_INET
		
        return bootstrap.bind(host: ipv4 ? "0.0.0.0" : "::", port: 0).map { channel in
            let client = DNSClient(
                channel: channel,
                address: address,
                decoder: dnsDecoder
            )

            dnsDecoder.mainClient = client
            return client
        }
    }
    
    /// Connect to the dns server using TCP and return a future with the client.
    /// - parameters:
    ///    - group: EventLoops to use
    ///    - config: DNS servers to connect to
    /// - returns: Future with the NioDNS client
    public static func connectTCP(on group: EventLoopGroup, config: [SocketAddress]) -> EventLoopFuture<DNSClient> {
        guard let address = config.preferred else {
            return group.next().makeFailedFuture(MissingNameservers())
        }
        
        let dnsDecoder = DNSDecoder(group: group)
        
        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                return channel.pipeline.addHandlers(
                    ByteToMessageHandler(UInt16FrameDecoder()),
                    MessageToByteHandler(UInt16FrameEncoder()),
                    dnsDecoder,
                    DNSEncoder()
                )
            }
        
        return bootstrap.connect(to: address).map { channel in
            let client = DNSClient(
                channel: channel,
                address: address,
                decoder: dnsDecoder
            )
            
            dnsDecoder.mainClient = client
            return client
        }
    }
}

fileprivate extension Array where Element == SocketAddress {
    var preferred: SocketAddress? {
		return first(where: { $0.protocol.rawValue == PF_INET }) ?? first
    }
}

#if canImport(NIOTransportServices) && os(iOS)
import NIOTransportServices

@available(iOS 12, *)
extension DNSClient {
    /// Connect to the dns server using TCP using NIOTransportServices. This is only available on iOS 12 and above.
    /// - parameters:
    ///   - group: EventLoops to use
    ///   - config: DNS servers to use
    /// - returns: Future with the NioDNS client. Use 
    public static func connectTS(on group: NIOTSEventLoopGroup, config: [SocketAddress]) -> EventLoopFuture<DNSClient> {
        guard let address = config.preferred else {
            return group.next().makeFailedFuture(MissingNameservers())
        }

        let dnsDecoder = DNSDecoder(group: group)
        
        return NIOTSDatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.addHandlers(dnsDecoder, DNSEncoder())
        }
        .connect(to: address)
        .map { channel -> DNSClient in
            let client = DNSClient(
                channel: channel,
                address: address,
                decoder: dnsDecoder
            )

            dnsDecoder.mainClient = client
            return client
        }
    }
    /// Connect to the dns server using TCP using NIOTransportServices. This is only available on iOS 12 and above.
    /// The DNS Host is read from /etc/resolv.conf
    /// - parameters:
    ///   - group: EventLoops to use
    public static func connectTS(on group: NIOTSEventLoopGroup) -> EventLoopFuture<DNSClient> {
        do {
            let configString = try String(contentsOfFile: "/etc/resolv.conf")
            let config = try ResolvConf(from: configString)

            return connectTS(on: group, config: config.nameservers)
        } catch {
            return group.next().makeFailedFuture(UnableToParseConfig())
        }
    }
}
#endif
