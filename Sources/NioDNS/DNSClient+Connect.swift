import NIO
import Foundation

extension NioDNS {
    /// Connect to the dns server
    ///
    /// - parameters:
    ///     - group: EventLoops to use
    /// - returns: Future with the NioDNS client
    public static func connect(on group: EventLoopGroup) -> EventLoopFuture<NioDNS> {
        do {
            let configString = try String(contentsOfFile: "/etc/resolv.conf")
            let config = try ResolvConf(from: configString)

            return connect(on: group, config: config.nameservers)
        } catch {
            return group.next().newFailedFuture(error: UnableToParseConfig())
        }
    }

    /// Connect to the dns server
    ///
    /// - parameters:
    ///     - group: EventLoops to use
    ///     - host: DNS host to connect to
    /// - returns: Future with the NioDNS client
    public static func connect(on group: EventLoopGroup, host: String) -> EventLoopFuture<NioDNS> {
        do {
            let address = try SocketAddress(ipAddress: host, port: 53)
            return connect(on: group, config: [address])
        } catch {
            return group.next().newFailedFuture(error: error)
        }
    }

    public static func connect(on group: EventLoopGroup, config: [SocketAddress]) -> EventLoopFuture<NioDNS> {
        guard let address = config.first else {
            return group.next().newFailedFuture(error: MissingNameservers())
        }

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
