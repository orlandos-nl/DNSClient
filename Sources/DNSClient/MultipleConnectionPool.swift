import NIO

public final class MultipleConnectionPool: DNSConnectionPool {
    /// A list of currently open connections
    ///
    /// This is not thread safe outside of the cluster's eventloop
    private var pool: [DNSClient]
    public let eventLoop: EventLoop
    
    /// If `true`, no connections will be opened and all existing connections will be shut down
    ///
    /// This is not thread safe outside of the cluster's eventloop
    private var isClosed = false
    
    init(on eventLoop: EventLoop) {
        self.eventLoop = eventLoop
        self.pool = []
    }
    
    public func next(for requirements: ConnectionRequirements) -> EventLoopFuture<DNSClient> {
        makeConnectionRecursively(for: requirements)
    }
    
    private func makeConnectionRecursively(for requirements: ConnectionRequirements, attempts: Int = 3) -> EventLoopFuture<DNSClient> {
        return makeConnection(for: requirements).flatMapError { error -> EventLoopFuture<DNSClient> in
            if attempts < 0 {
                return self.eventLoop.makeFailedFuture(error)
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
            return eventLoop.makeFailedFuture(ConnectionClosed())
        }
        
        let connectMethod = requirements.protocolPreference == .tcp ? DNSClient.connectTCP(on:config:) : DNSClient.connect(on:config:)
        
        return connectMethod(eventLoop, [requirements.host]).map { connection in
            connection.channel.closeFuture.whenComplete { [weak self, connection] _ in
                guard let me = self else { return }
                me.remove(connection: connection)
            }
            return connection
        }
    }
    
    func getConnection(for requirements: ConnectionRequirements) -> EventLoopFuture<DNSClient> {
        if let foundConnection = findExistingConnection(for: requirements) {
            return self.eventLoop.makeSucceededFuture(foundConnection)
        }
        return self.createPooledConnection(for: requirements)
    }
    
    func findExistingConnection(for requirements: ConnectionRequirements) -> DNSClient? {
        return pool.first { connection in
            connection.primaryAddress == requirements.host && connection.connectionType == requirements.protocolPreference
        }
    }
            
    func remove(connection: DNSClient) {
        if let index = self.pool.firstIndex(where: { $0 === connection }) {
            self.pool.remove(at: index)
        }
    }
}
