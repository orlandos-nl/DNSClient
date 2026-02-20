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

    /// Creates a multicast DNS client for mDNS (RFC 6762).
    ///
    /// Joins the appropriate link-local multicast group and optionally pins
    /// outbound queries to a specific network interface.
    ///
    /// Per RFC 6762 Section 3, queries use `224.0.0.251` (IPv4) or `FF02::FB`
    /// (IPv6) on UDP port 5353. Per Section 14, multi-interface hosts need to
    /// specify which interface to use for link-local queries. Per Section 20,
    /// dual-stack hosts should query using both IPv4 and IPv6.
    ///
    /// - Parameters:
    ///   - group: EventLoops to use
    ///   - interface: Optional network device to bind multicast to. The device's
    ///     address family (IPv4 vs IPv6) determines which multicast group is joined.
    ///     When `nil`, the IPv4 multicast group is used and the kernel picks the
    ///     default interface.
    /// - Returns: Future with the MulticastDNSClient
    public static func connectMulticast(
        on group: EventLoopGroup,
        interface: NIONetworkDevice? = nil
    ) -> EventLoopFuture<MulticastDNSClient> {
        do {
            // Choose multicast group based on the interface's address family.
            // RFC 6762 §3: IPv4 uses 224.0.0.251, IPv6 uses FF02::FB, both on port 5353.
            let useIPv6: Bool
            if case .v6? = interface?.address { useIPv6 = true } else { useIPv6 = false }
            let address = try SocketAddress(
                ipAddress: useIPv6 ? "ff02::fb" : "224.0.0.251",
                port: 5353
            )

            return connect(on: group, config: [address]).flatMap { client in
                let channel = client.channel as! MulticastChannel
                let multicastClient = MulticastDNSClient(
                    channel: channel,
                    address: address,
                    decoder: client.dnsDecoder
                )
                let joinFuture = channel.joinGroup(address, device: interface)

                guard let interface = interface, let ifAddr = interface.address else {
                    return joinFuture.map { multicastClient }
                }

                let provider = client.channel as! SocketOptionProvider
                switch ifAddr {
                case .v4(let v4):
                    // RFC 6762 §14: Pin outbound multicast to this IPv4 interface
                    // so queries leave on the correct NIC rather than the kernel default.
                    return joinFuture.flatMap {
                        provider.setIPMulticastIF(v4.address.sin_addr)
                    }.map { multicastClient }
                case .v6:
                    // RFC 6762 §20: For IPv6, set IPV6_MULTICAST_IF using the
                    // interface index so outbound queries use the correct link.
                    return joinFuture.flatMap {
                        provider.setIPv6MulticastIF(CUnsignedInt(interface.interfaceIndex))
                    }.map { multicastClient }
                default:
                    return joinFuture.map { multicastClient }
                }
            }
        } catch {
            return group.next().makeFailedFuture(UnableToParseConfig())
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

#if canImport(Network)
import NIOTransportServices

@available(iOS 12, *)
extension DNSClient {
    public static func connectTS(on group: NIOTSEventLoopGroup, host: String) -> EventLoopFuture<DNSClient> {
        do {
            let address = try SocketAddress(ipAddress: host, port: 53)
            return connectTS(on: group, config: [address])
        } catch {
            return group.next().makeFailedFuture(error)
        }
    }

    /// Connect to the dns server using TCP using NIOTransportServices. This is only available on iOS 12 and above.
    /// - parameters:
    ///   - group: EventLoops to use
    ///   - config: DNS servers to use
    /// - returns: Future with the NioDNS client. Use 
    public static func connectTS(on group: NIOTSEventLoopGroup, config: [SocketAddress]) -> EventLoopFuture<DNSClient> {
        // Don't connect by UNIX domain socket. We currently don't intend to test & support that.
        guard
            let address = config.preferred,
            let ipAddress = address.ipAddress,
            let port = address.port
        else {
            return group.next().makeFailedFuture(MissingNameservers())
        }

        let dnsDecoder = DNSDecoder(group: group)
        
        return NIOTSDatagramBootstrap(group: group).channelInitializer { channel in
            return channel.pipeline.addHandlers(dnsDecoder, DNSEncoder())
        }
        .connect(host: ipAddress, port: port)
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

    public static func connectTSTCP(on group: NIOTSEventLoopGroup, host: String) -> EventLoopFuture<DNSClient> {
        do {
            let address = try SocketAddress(ipAddress: host, port: 53)
            return connectTSTCP(on: group, config: [address])
        } catch {
            return group.next().makeFailedFuture(error)
        }
    }

    /// Connect to the dns server using TCP using NIOTransportServices. This is only available on iOS 12 and above.
    /// - parameters:
    ///   - group: EventLoops to use
    ///   - config: DNS servers to use
    /// - returns: Future with the NioDNS client. Use 
    public static func connectTSTCP(on group: NIOTSEventLoopGroup, config: [SocketAddress]) -> EventLoopFuture<DNSClient> {
        guard let address = config.preferred else {
            return group.next().makeFailedFuture(MissingNameservers())
        }

        let dnsDecoder = DNSDecoder(group: group)
        
        return NIOTSConnectionBootstrap(group: group).channelInitializer { channel in
            return channel.pipeline.addHandlers(
                ByteToMessageHandler(UInt16FrameDecoder()),
                MessageToByteHandler(UInt16FrameEncoder()),
                dnsDecoder,
                DNSEncoder()
            )
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
    public static func connectTSTCP(on group: NIOTSEventLoopGroup) -> EventLoopFuture<DNSClient> {
        do {
            let configString = try String(contentsOfFile: "/etc/resolv.conf")
            let config = try ResolvConf(from: configString)

            return connectTSTCP(on: group, config: config.nameservers)
        } catch {
            return group.next().makeFailedFuture(UnableToParseConfig())
        }
    }
}
#endif
