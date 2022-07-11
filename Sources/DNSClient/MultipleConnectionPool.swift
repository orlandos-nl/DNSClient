import NIO

public final class MultipleConnectionPool: DNSConnectionPool {
    /// A list of currently open connections
    ///
    /// This is not thread safe outside of the cluster's eventloop
    internal var pool: [PooledConnection]
    public let eventLoop: EventLoop
    
    /// If `true`, no connections will be opened and all existing connections will be shut down
    ///
    /// This is not thread safe outside of the cluster's eventloop
    private var isClosed = false
    
    public init(on eventLoop: EventLoop) {
        self.eventLoop = eventLoop
        self.pool = []
    }
    
    public func next(for requirements: ConnectionRequirements) -> EventLoopFuture<DNSClient> {
        makeConnectionRecursively(for: requirements)
    }
    
    private func makeConnectionRecursively(for requirements: ConnectionRequirements, attempts: Int = 3) -> EventLoopFuture<DNSClient> {
        return makeConnection(for: requirements).map { $0.connection }.flatMapError { error -> EventLoopFuture<DNSClient> in
            if attempts < 0 {
                return self.eventLoop.makeFailedFuture(error)
            }
            
            return self.makeConnectionRecursively(for: requirements, attempts: attempts - 1)
        }
    }
    
    private func makeConnection(for requirements: ConnectionRequirements) -> EventLoopFuture<PooledConnection> {
        switch requirements.sourcingPreference {
        case .new:
            return createPooledConnection(for: requirements)
        case .unpooled:
            return createUnpooledConnection(for: requirements)
        case .existing:
            return getConnection(for: requirements)
        }
    }
    
    private func createPooledConnection(for requirements: ConnectionRequirements) -> EventLoopFuture<PooledConnection> {
        // create an unpooled connection and add it to the pool
        return createUnpooledConnection(for: requirements).map { connection in
            self.pool.append(connection)
            return connection
        }
    }
    
    private func createUnpooledConnection(for requirements: ConnectionRequirements) -> EventLoopFuture<PooledConnection> {
        if isClosed {
            return eventLoop.makeFailedFuture(ConnectionClosed())
        }
        
        let connectMethod = requirements.protocolPreference == .tcp ? DNSClient.connectTCP(on:host:port:) : DNSClient.connect(on:host:port:)
        
        return connectMethod(eventLoop, requirements.host, requirements.port).map { connection in
            connection.channel.closeFuture.whenComplete { [weak self, connection] _ in
                guard let me = self else { return }
                me.remove(connection: connection)
            }
            return connection
        }.map { connection in
            return PooledConnection(connection: connection, connectionType: requirements.protocolPreference)
        }
    }
    
    private func getConnection(for requirements: ConnectionRequirements) -> EventLoopFuture<PooledConnection> {
        do {
            if let foundConnection = try findExistingConnection(for: requirements) {
                return self.eventLoop.makeSucceededFuture(foundConnection)
            }
            return self.createPooledConnection(for: requirements)
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }
    
    private func findExistingConnection(for requirements: ConnectionRequirements) throws -> PooledConnection? {
        let address = try SocketAddress(ipAddress: requirements.host, port: requirements.port)
        return pool.first { connection in
            connection.connection.primaryAddress == address && connection.connectionType == requirements.protocolPreference
        }
    }
            
    private func remove(connection: DNSClient) {
        if let index = self.pool.firstIndex(where: { $0.connection === connection }) {
            self.pool.remove(at: index)
        }
    }
    
    public func disconnect() -> EventLoopFuture<Void> {
        self.eventLoop.flatSubmit {
            self.isClosed = true
            let connections = self.pool
            self.pool = []
            
            let closed = connections.map { connection in
                connection.connection.close()
            }
            
            return EventLoopFuture<Void>.andAllComplete(closed, on: self.eventLoop)
        }
    }
}

struct PooledConnection {
    let connection: DNSClient
    let connectionType: ConnectionRequirements.ConnectionType
}
