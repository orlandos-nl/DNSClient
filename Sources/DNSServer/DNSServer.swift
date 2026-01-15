import NIO
import NIOConcurrencyHelpers
import DNSProtocol

/// Configuration for the DNS server.
public struct DNSServerConfiguration: Sendable {
    /// The host address to bind to. Defaults to "0.0.0.0" for all interfaces.
    public var host: String

    /// The port to listen on. Defaults to 53 (standard DNS port).
    public var port: Int

    /// Whether to enable UDP transport.
    public var enableUDP: Bool

    /// Whether to enable TCP transport.
    public var enableTCP: Bool

    /// Maximum message size for UDP responses (default 512, can be up to 65535 with EDNS).
    public var maxUDPResponseSize: Int

    public init(
        host: String = "0.0.0.0",
        port: Int = 53,
        enableUDP: Bool = true,
        enableTCP: Bool = true,
        maxUDPResponseSize: Int = 512
    ) {
        self.host = host
        self.port = port
        self.enableUDP = enableUDP
        self.enableTCP = enableTCP
        self.maxUDPResponseSize = maxUDPResponseSize
    }
}

/// A DNS server that handles queries via a delegate.
public final class DNSServer: Sendable {
    private let configuration: DNSServerConfiguration
    private let delegate: DNSServerDelegate
    private let eventLoopGroup: EventLoopGroup

    // Channel references (need to be thread-safe)
    private let udpChannel: NIOLockedValueBox<Channel?>
    private let tcpChannel: NIOLockedValueBox<Channel?>

    /// The actual bound port for UDP (useful when binding to port 0).
    public var udpPort: Int? {
        udpChannel.withLockedValue { $0?.localAddress?.port }
    }

    /// The actual bound port for TCP (useful when binding to port 0).
    public var tcpPort: Int? {
        tcpChannel.withLockedValue { $0?.localAddress?.port }
    }

    /// Create a new DNS server.
    ///
    /// - Parameters:
    ///   - configuration: Server configuration options.
    ///   - delegate: The delegate to handle incoming queries.
    ///   - eventLoopGroup: The event loop group to use.
    public init(
        configuration: DNSServerConfiguration = DNSServerConfiguration(),
        delegate: DNSServerDelegate,
        eventLoopGroup: EventLoopGroup
    ) {
        self.configuration = configuration
        self.delegate = delegate
        self.eventLoopGroup = eventLoopGroup
        self.udpChannel = NIOLockedValueBox(nil)
        self.tcpChannel = NIOLockedValueBox(nil)
    }

    /// Start the DNS server.
    public func start() async throws {
        if configuration.enableUDP {
            let channel = try await startUDPServer()
            udpChannel.withLockedValue { $0 = channel }
        }

        if configuration.enableTCP {
            let channel = try await startTCPServer()
            tcpChannel.withLockedValue { $0 = channel }
        }
    }

    /// Stop the DNS server gracefully.
    public func stop() async throws {
        if let channel = udpChannel.withLockedValue({ $0 }) {
            try await channel.close()
        }
        if let channel = tcpChannel.withLockedValue({ $0 }) {
            try await channel.close()
        }
    }

    // MARK: - Private

    private func startUDPServer() async throws -> Channel {
        let bootstrap = DatagramBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { [delegate, configuration] channel in
                channel.pipeline.addHandler(
                    DNSServerUDPHandler(delegate: delegate, configuration: configuration)
                )
            }

        return try await bootstrap.bind(host: configuration.host, port: configuration.port).get()
    }

    private func startTCPServer() async throws -> Channel {
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [delegate] channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(UInt16FrameDecoder()),
                    MessageToByteHandler(UInt16FrameEncoder()),
                    DNSServerTCPHandler(delegate: delegate)
                ])
            }
            .childChannelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)

        return try await bootstrap.bind(host: configuration.host, port: configuration.port).get()
    }
}
