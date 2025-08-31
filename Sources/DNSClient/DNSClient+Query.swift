import NIO
import NIOConcurrencyHelpers

extension DNSClient {
    /// Request A records
    ///
    /// - parameters:
    ///     - host: The hostname address to request the records from
    ///     - port: The port to use
    /// - returns: A future of SocketAddresses
    public func initiateAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        let result = self.sendQuery(forHost: host, type: .a)

        return result.map { message in
            return message.answers.compactMap { answer in
                guard case .a(let record) = answer else {
                    return nil
                }

                return try? record.resource.address.socketAddress(port: port)
            }
        }
    }

    /// Request AAAA records
    ///
    /// - parameters:
    ///     - host: The hostname address to request the records from
    ///     - port: The port to use
    /// - returns: A future of SocketAddresses
    public func initiateAAAAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        let result = self.sendQuery(forHost: host, type: .aaaa)

        return result.map { message in
            return message.answers.compactMap { answer -> SocketAddress? in
                guard
                    case .aaaa(let record) = answer,
                    record.resource.address.count == 16
                else {
                    return nil
                }

                let address = record.resource.address
                
                let scopeID: UInt32 = 0 // More info about scope_id/zone_id https://tools.ietf.org/html/rfc6874#page-3
                let flowinfo: UInt32 = 0 // More info about flowinfo https://tools.ietf.org/html/rfc6437#page-4
                
                #if canImport(Glibc)
                let ipAddress = address.withUnsafeBytes { buffer in
                    return buffer.bindMemory(to: in6_addr.__Unnamed_union___in6_u.self).baseAddress!.pointee
                }
                let sockaddr = sockaddr_in6(sin6_family: sa_family_t(AF_INET6), sin6_port: in_port_t(port), sin6_flowinfo: flowinfo, sin6_addr: in6_addr(__in6_u: ipAddress), sin6_scope_id: scopeID)
                #elseif canImport(Musl)
                let ipAddress = address.withUnsafeBytes { buffer in
                    return buffer.bindMemory(to: in6_addr.__Unnamed_union___in6_union.self).baseAddress!.pointee
                }
                let sockaddr = sockaddr_in6(sin6_family: sa_family_t(AF_INET6), sin6_port: in_port_t(port), sin6_flowinfo: flowinfo, sin6_addr: in6_addr(__in6_union: ipAddress), sin6_scope_id: scopeID)
                #else
                let ipAddress = address.withUnsafeBytes { buffer in
                    return buffer.bindMemory(to: in6_addr.__Unnamed_union___u6_addr.self).baseAddress!.pointee
                }
                let size = MemoryLayout<sockaddr_in6>.size
                let sockaddr = sockaddr_in6(sin6_len: numericCast(size), sin6_family: sa_family_t(AF_INET6), sin6_port: in_port_t(port), sin6_flowinfo: flowinfo, sin6_addr: in6_addr(__u6_addr: ipAddress), sin6_scope_id: scopeID)
                #endif

                return SocketAddress(sockaddr, host: host)
            }
        }
    }

    /// Cancel all queries that are currently running. This will fail all futures with a `CancelError`
    public func cancelQueries() {
        dnsDecoder.messageCache.withLockedValue { cache in
            for (id, query) in cache {
                cache[id] = nil
                query.promise.fail(CancelError())
            }
        }
    }

    /// Send a question to the dns host
    ///
    /// - Parameters:
    ///     - address: The hostname address to request a certain resource from
    ///     - type: The resource you want to request
    ///     - additionalOptions: Additional message options
    ///     - timeout: Timeout for this query (default: 30s to preserve existing behavior)
    /// - Returns: A future with the response message
    public func sendQuery(
        forHost address: String,
        type: DNSResourceType,
        additionalOptions: MessageOptions? = nil,
        timeout: TimeAmount = .seconds(30)
    ) -> EventLoopFuture<Message> {
        channel.eventLoop.flatSubmit {
            let messageID = self.messageID.withLockedValue { id in
                let newID = id &+ 1
                id = newID
                return id
            }
            
            var options: MessageOptions = [.standardQuery]
            
            if !self.isMulticast {
                options.insert(.recursionDesired)
            }
            
            if let additionalOptions = additionalOptions {
                options.insert(additionalOptions)
            }
            
            let header = DNSMessageHeader(id: messageID, options: options, questionCount: 1, answerCount: 0, authorityCount: 0, additionalRecordCount: 0)
            let labels = address.split(separator: ".").map(String.init).map(DNSLabel.init)
            let question = QuestionSection(labels: labels, type: type, questionClass: .internet)
            let message = Message(header: header, questions: [question], answers: [], authorities: [], additionalData: [])
            
            return self.send(message, to: nil, timeout: timeout)
        }
    }

    // MARK: - Transport primitive (timeout-aware overload + wrapper)
    
    /// Historical behavior wrapper (30s default); forwards to timeout-aware overload.
    /// Keeping this avoids any source change for existing callers.
    func send(_ message: Message, to address: SocketAddress? = nil) -> EventLoopFuture<Message> {
        return self.send(message, to: address, timeout: .seconds(30))
    }
    
    /// Timeout-aware transport primitive with proper cancellation and cache cleanup.
    ///
    /// Timers are canceled on success, and in‑flight entries are removed on timeout.
    ///
    /// - Parameters:
    ///   - message: The complete DNS `Message` to be sent as a query.
    ///   - address: The destination `SocketAddress` for this specific query. If `nil`, the client's
    ///              default server address is used.
    ///   - timeout: The maximum `TimeAmount` to wait for a response before the returned future
    ///              fails with a timeout error.
    /// - Returns: An `EventLoopFuture<Message>` that will be fulfilled with the server's
    ///           response message, or fail if an error occurs (e.g., a timeout).
    func send(_ message: Message, to address: SocketAddress? = nil, timeout: TimeAmount) -> EventLoopFuture<Message> {
        let promise: EventLoopPromise<Message> = loop.makePromise()
        
        return loop.flatSubmit {
            // Register in-flight
            self.dnsDecoder.messageCache.withLockedValue { cache in
                cache[message.header.id] = SentQuery(message: message, promise: promise)
            }
            
            // Write on the channel
            self.channel.writeAndFlush(message, promise: nil)
            
            struct DNSTimeoutError: Error {}
            
            // Schedule a timeout that also removes the in-flight cache entry to avoid leaks
            let timeoutTask = self.loop.scheduleTask(in: timeout) { [messageCache = dnsDecoder.messageCache] in
                messageCache.withLockedValue { cache in
                    cache[message.header.id] = nil
                }
                promise.fail(DNSTimeoutError())
            }
            
            // Ensure timer is cancelled once the promise resolves
            promise.futureResult.whenComplete { _ in
                // a successful promise cancels, a failed promise canceled is a no-op.
                timeoutTask.cancel()
            }
            
            return promise.futureResult
        }
    }
    
    /// Request SRV records from a host
    ///
    /// - parameters:
    ///     - host: Hostname to get the records from
    /// - returns: A future with the resource record
    public func getSRVRecords(from host: String) -> EventLoopFuture<[ResourceRecord<SRVRecord>]> {
        return self.sendQuery(forHost: host, type: .srv).map { message in
            return message.answers.compactMap { answer in
                guard case .srv(let record) = answer else {
                    return nil
                }

                return record
            }
        }
    }

    /// Request NS records for a domain
    ///
    /// - parameters:
    ///     - host: Hostname to get the records from
    /// - returns: A future with an array of resource records
    public func initiateNSQuery(forDomain domain: String) -> EventLoopFuture<[ResourceRecord<NSRecord>]> {
        return self.sendQuery(forHost: domain, type: .ns).map { message in
            return message.answers.compactMap { answer in
                guard case .ns(let record) = answer else { return nil }

                return record
            }
        }
    }

    /// Request SOA records from a host
    ///
    /// - parameters:
    ///     - host: Hostname to get the records from
    /// - returns: A future with an array of resource records
    public func initiateSOAQuery(forDomain domain: String) -> EventLoopFuture<[ResourceRecord<SOARecord>]> {
        return self.sendQuery(forHost: domain, type: .soa).map { message in
            return message.answers.compactMap { answer in
                guard case .soa(let record) = answer else { return nil }

                return record
            }
        }
    }
}
