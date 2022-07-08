import NIO

public final class MultipleConnectionPool: DNSConnectionPool {
    private var pool: [DNSClient]
    
    /// If `true`, no connections will be opened and all existing connections will be shut down
    private var isClosed = false
    
    private var elg: EventLoopGroup
    
    init(on group: EventLoopGroup) {
        self.pool = []
        self.elg = group
    }
    
    public func next(for requirements: ConnectionRequirements) -> EventLoopFuture<DNSClient> {
        makeConnectionRecursively(for: requirements)
    }
    
    private func makeConnectionRecursively(for requirements: ConnectionRequirements, attempts: Int = 3) -> EventLoopFuture<DNSClient> {
        return makeConnection(for: requirements).flatMapError { error -> EventLoopFuture<DNSClient> in
            if attempts < 0 {
                return self.elg.next().makeFailedFuture(error)
            }
            
            return self.makeConnectionRecursively(for: requirements, attempts: attempts - 1)
        }
    }
    
    private func makeConnection(for requirements: ConnectionRequirements) -> EventLoopFuture<DNSClient> {
        switch requirements.sourcingPreference {
        case .new:
            return createPooledConnection(for: requirements)
        case .unpooled:
            return createUnpooledConnection(for: requirements)
        case .existing:
            return getConnection(for: requirements)
        }
    }
    
    func createPooledConnection(for requirements: ConnectionRequirements) -> EventLoopFuture<DNSClient> {
        // create an unpooled connection and add it to the pool
        return createUnpooledConnection(for: requirements).map { connection in
            self.pool.append(connection)
            return connection
        }
    }
    
    func createUnpooledConnection(for requirements: ConnectionRequirements) -> EventLoopFuture<DNSClient> {
        if isClosed {
            return elg.next().makeFailedFuture(ConnectionClosed())
        }
        
        let connectMethod = requirements.protocolPreference == .tcp ? DNSClient.connectTCP(on:config:) : DNSClient.connect(on:config:)
        
        return connectMethod(elg, [requirements.host]).map { connection in
            connection.channel.closeFuture.whenComplete { [weak self, connection] _ in
                guard let me = self else { return }
                me.remove(connection: connection)
            }
            return connection
        }
    }
    
    func getConnection(for requirements: ConnectionRequirements) -> EventLoopFuture<DNSClient> {
        if let foundConnection = findExistingConnection(for: requirements) {
            return self.elg.next().makeSucceededFuture(foundConnection)
        }
        return self.createPooledConnection(for: requirements)
    }
    
    func findExistingConnection(for requirements: ConnectionRequirements) -> DNSClient? {
        return pool.first { connection in
            connection.primaryAddress == requirements.host
            // check protocol
        }
    }
            
    func remove(connection: DNSClient) {
        if let index = self.pool.firstIndex(where: { $0 === connection }) {
            self.pool.remove(at: index)
        }
    }
}
