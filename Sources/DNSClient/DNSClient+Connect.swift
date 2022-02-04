import NIO
import Foundation

extension DNSClient {
    public convenience init(servers: [SocketAddress]? = nil) async throws {
        let nameservers: [SocketAddress]
        
        if let servers = servers {
            nameservers = servers
        } else {
            let configString = try String(contentsOfFile: "/etc/resolv.conf")
            let config = try ResolvConf(from: configString)
            
            nameservers = config.nameservers
        }
        
        guard let address = nameservers.preferred else {
            throw MissingNameservers()
        }
        
        let dnsDecoder = DNSDecoder()
        
        #if canImport(NIOTransportServices) && os(iOS)
        let channel = try await NIOTSDatagramBootstrap(group: NIOTSEventLoopGroup(loopCount: 1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.addHandlers(dnsDecoder, DNSEncoder())
            }
            .connect(to: address)
            .get()
        #else
        let bootstrap = DatagramBootstrap(group: MultiThreadedEventLoopGroup(numberOfThreads: 1))
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
        
        let channel = try await bootstrap.bind(host: ipv4 ? "0.0.0.0" : "::", port: 0).get()
        #endif
        
        self.init(
            channel: channel,
            address: address,
            decoder: dnsDecoder
        )
        
        dnsDecoder.mainClient = self
    }
}

fileprivate extension Array where Element == SocketAddress {
    var preferred: SocketAddress? {
		return first(where: { $0.protocol.rawValue == PF_INET }) ?? first
    }
}
