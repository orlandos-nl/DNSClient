import NIO

extension NioDNS {
    /// Connect to the dns server
    ///
    /// - parameters:
    ///     - group: EventLoops to use
    /// - returns: Future with the NioDNS client
    public static func connect(on group: EventLoopGroup) -> EventLoopFuture<NioDNS> {
        let address: SocketAddress

        if ipv4DnsServer.sin_addr.s_addr != 0 {
            address = withUnsafeBytes(of: ipv4DnsServer.sin_addr.s_addr) { buffer in
                let buffer = buffer.bindMemory(to: UInt8.self)
                let name = "\(buffer[0]).\(buffer[1]).\(buffer[2]).\(buffer[3])"
                return SocketAddress(ipv4DnsServer, host: name)
            }
        } else {
            // TODO: Create string hostname
            address = SocketAddress(ipv6DnsServer, host: "")
        }

        return connect(on: group, address: address)
    }

    /// Connect to the dns server
    ///
    /// - parameters:
    ///     - group: EventLoops to use
    ///     - host: DNS host to connect to
    /// - returns: Future with the NioDNS client
    public static func connect(on group: EventLoopGroup, host: String) -> EventLoopFuture<NioDNS> {
        do {
            return connect(on: group, address: try SocketAddress(ipAddress: host, port: 53))
        } catch {
            return group.next().newFailedFuture(error: error)
        }
    }

    public static func connect(on group: EventLoopGroup, address: SocketAddress) -> EventLoopFuture<NioDNS> {
        let dnsDecoder = DNSDecoder(group: group)

        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.add(handler: dnsDecoder).then {
                    return channel.pipeline.add(handler: DNSEncoder())
                }
        }

        let ipv4 = address.protocolFamily == PF_INET
        return bootstrap.bind(host: ipv4 ? "0.0.0.0" : "::1", port: 0).map { channel in
            let client = NioDNS(
                channel: channel,
                address: address,
                decoder: dnsDecoder
            )

            dnsDecoder.mainClient = client
            return client
        }
    }
}
