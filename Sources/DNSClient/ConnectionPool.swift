import NIO

public struct ConnectionRequirements: Hashable {
    public enum SourcingPreference {
        case new, existing, unpooled
    }
    
    var sourcingPreference: SourcingPreference
    var protocolPreference: DNSClient.ConnectionType
    var host: SocketAddress

    public init(sourcingPreference: SourcingPreference = .existing, protocolPreference: DNSClient.ConnectionType, host: SocketAddress) {
        self.sourcingPreference = sourcingPreference
        self.protocolPreference = protocolPreference
        self.host = host
    }
}

public protocol DNSConnectionPool {
    func next(for requirements: ConnectionRequirements) -> EventLoopFuture<DNSClient>
}

extension DNSClient: DNSConnectionPool {
    public func next(for request: ConnectionRequirements) -> EventLoopFuture<DNSClient> {
        loop.makeSucceededFuture(self)
    }
}
