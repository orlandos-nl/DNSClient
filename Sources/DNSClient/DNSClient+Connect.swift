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
                decoder: dnsDecoder,
                connectionType: .udp
            )

            dnsDecoder.mainClient = client
            return client
        }
    }
    
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
                decoder: dnsDecoder,
                connectionType: .tcp
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
    /// Connect to the dns server
    ///
    /// - parameters:
    ///     - group: EventLoops to use
    /// - returns: Future with the NioDNS client
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
