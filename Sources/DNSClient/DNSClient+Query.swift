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
                query.continuation.finish(throwing: CancellationError())
            }
        }
    }

    /// Send a question to the dns host
    ///
    /// - parameters:
    ///     - address: The hostname address to request a certain resource from
    ///     - type: The resource you want to request
    ///     - additionalOptions: Additional message options
    /// - returns: A future with the response message
    public func withResults<T: Sendable>(
        forHost address: String,
        type: DNSResourceType,
        additionalOptions: MessageOptions? = nil,
        to remote: SocketAddress? = nil,
        perform: (AsyncThrowingStream<Message, any Error>) async throws -> T
    ) async throws -> T {
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

        let results = try await self.send(message, to: remote)
        return try await perform(results)
    }

    /// Send a question to the dns host
    ///
    /// - parameters:
    ///     - address: The hostname address to request a certain resource from
    ///     - type: The resource you want to request
    ///     - additionalOptions: Additional message options
    /// - returns: A future with the response message
    public func sendQuery(
        forHost address: String,
        type: DNSResourceType,
        additionalOptions: MessageOptions? = nil
    ) -> EventLoopFuture<Message> {
        self.channel.eventLoop.makeFutureWithTask {
            try await self.withResults(forHost: address, type: type, additionalOptions: additionalOptions) { results in
                for try await result in results {
                    return result
                }
                
                throw DNSTimeoutError()
            }
        }
    }

    func send(_ message: Message, to address: SocketAddress? = nil) async throws -> AsyncThrowingStream<Message, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Message, any Error>.makeStream()

        try await loop.submit {
            self.dnsDecoder.messageCache.withLockedValue { cache in
                cache[message.header.id] = SentQuery(message: message, continuation: continuation)
            }
            let messageWithAddress = AddressedEnvelope(
                remoteAddress: address ?? self.primaryAddress,
                data: message
            )
            self.channel.writeAndFlush(messageWithAddress, promise: nil)

            self.loop.scheduleTask(in: self.timeout) {
                continuation.finish()
                self.dnsDecoder.messageCache.withLockedValue { cache in
                    cache[message.header.id] = nil
                }
            }
        }.get()

        return stream
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
}
