import NIO

extension NioDNS {
    /// Request A records
    ///
    /// - parameters:
    ///     - host: The hostname address to request the records from
    ///     - port: The port to use
    /// - returns: A future of SocketAddresses
    public func initiateAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        let result = self.sendQuery(forHost: host, type: .a)

        return result.thenThrowing { message in
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
            return message.answers.compactMap { answer in
                guard
                    case .aaaa(let record) = answer,
                    record.resource.address.count == 16
                    else {
                        return nil
                }

                let address = record.resource.address
                
                let scopeID: UInt32 = 0 // More info about scope_id/zone_id https://tools.ietf.org/html/rfc6874#page-3
                let flowinfo: UInt32 = 0 // More info about flowinfo https://tools.ietf.org/html/rfc6437#page-4
                
                #if os(Linux)
                let ipAddress = address.withUnsafeBytes { buffer in
                    return buffer.bindMemory(to: in6_addr.__Unnamed_union___in6_u.self).baseAddress!.pointee
                }
                let sockaddr = sockaddr_in6(sin6_family: sa_family_t(AF_INET6), sin6_port: in_port_t(port), sin6_flowinfo: flowinfo, sin6_addr: in6_addr(__in6_u: ipAddress), sin6_scope_id: scopeID)
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

    /// Cancel all queries
    public func cancelQueries() {
        for (id, query) in dnsDecoder.messageCache {
            dnsDecoder.messageCache[id] = nil
            query.promise.fail(error: CancelError())
        }
    }

    /// Send a question to the dns host
    ///
    /// - parameters:
    ///     - address: The hostname address to request a certain resource from
    ///     - type: The resource you want to request
    ///     - additionalOptions: Additional message options
    /// - returns: A future with the response message
    public func sendQuery(forHost address: String, type: ResourceType, additionalOptions: MessageOptions? = nil) -> EventLoopFuture<Message> {
        messageID = messageID &+ 1

        var options: MessageOptions = [.standardQuery, .recursionDesired]
        if let additionalOptions = additionalOptions {
            options.insert(additionalOptions)
        }

        let header = MessageHeader(id: messageID, options: options, questionCount: 1, answerCount: 0, authorityCount: 0, additionalRecordCount: 0)
        let labels = address.split(separator: ".").map(String.init).map(DNSLabel.init)
        let question = QuestionSection(labels: labels, type: type, questionClass: .internet)
        let message = Message(header: header, questions: [question], answers: [], authorities: [], additionalData: [])

        return send(message)
    }

    func send(_ message: Message, to address: SocketAddress? = nil) -> EventLoopFuture<Message> {
        let promise: EventLoopPromise<Message> = loop.newPromise()
        dnsDecoder.messageCache[message.header.id] = SentQuery(message: message, promise: promise)

        channel.writeAndFlush(AddressedEnvelope(remoteAddress: address ?? primaryAddress, data: message), promise: nil)

        return promise.futureResult
    }

    /// Request SRV records from a host
    ///
    /// - parameters:
    ///     - host: Hostname to get the records from
    /// - returns: A future with the resource record
    public func getSRVRecords(from host: String) -> EventLoopFuture<[ResourceRecord<SRVRecord>]> {
        return self.sendQuery(forHost: host, type: .srv).thenThrowing { message in
            return message.answers.compactMap { answer in
                guard case .srv(let record) = answer else {
                    return nil
                }

                return record
            }
        }
    }
}
