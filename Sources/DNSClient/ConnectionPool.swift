import NIO

public struct ConnectionRequirements: Hashable {
    public enum SourcingPreference {
        case new, existing, unpooled
    }
    
    public enum ConnectionType {
        case tcp, udp
    }
    
    var sourcingPreference: SourcingPreference
    var protocolPreference: ConnectionType
    var host: String
    var port: Int

    public init(sourcingPreference: SourcingPreference = .existing, protocolPreference: ConnectionType = .udp, host: String, port: Int = 53) {
        self.sourcingPreference = sourcingPreference
        self.protocolPreference = protocolPreference
        self.host = host
        self.port = port
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
