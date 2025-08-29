import DNSMessage
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
            message.answers.compactMap { answer in
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
            message.answers.compactMap { answer -> SocketAddress? in
                guard
                    case .aaaa(let record) = answer,
                    record.resource.address.count == 16
                else {
                    return nil
                }

                let address = record.resource.address

                let scopeID: UInt32 = 0  // More info about scope_id/zone_id https://tools.ietf.org/html/rfc6874#page-3
                let flowinfo: UInt32 = 0  // More info about flowinfo https://tools.ietf.org/html/rfc6437#page-4

                #if canImport(Glibc)
                let ipAddress = address.withUnsafeBytes { buffer in
                    buffer.bindMemory(to: in6_addr.__Unnamed_union___in6_u.self).baseAddress!.pointee
                }
                let sockaddr = sockaddr_in6(
                    sin6_family: sa_family_t(AF_INET6),
                    sin6_port: in_port_t(port),
                    sin6_flowinfo: flowinfo,
                    sin6_addr: in6_addr(__in6_u: ipAddress),
                    sin6_scope_id: scopeID
                )
                #elseif canImport(Musl)
                let ipAddress = address.withUnsafeBytes { buffer in
                    buffer.bindMemory(to: in6_addr.__Unnamed_union___in6_union.self).baseAddress!.pointee
                }
                let sockaddr = sockaddr_in6(
                    sin6_family: sa_family_t(AF_INET6),
                    sin6_port: in_port_t(port),
                    sin6_flowinfo: flowinfo,
                    sin6_addr: in6_addr(__in6_union: ipAddress),
                    sin6_scope_id: scopeID
                )
                #else
                let ipAddress = address.withUnsafeBytes { buffer in
                    buffer.bindMemory(to: in6_addr.__Unnamed_union___u6_addr.self).baseAddress!.pointee
                }
                let size = MemoryLayout<sockaddr_in6>.size
                let sockaddr = sockaddr_in6(
                    sin6_len: numericCast(size),
                    sin6_family: sa_family_t(AF_INET6),
                    sin6_port: in_port_t(port),
                    sin6_flowinfo: flowinfo,
                    sin6_addr: in6_addr(__u6_addr: ipAddress),
                    sin6_scope_id: scopeID
                )
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

            let header = DNSMessageHeader(
                id: messageID,
                options: options,
                questionCount: 1,
                answerCount: 0,
                authorityCount: 0,
                additionalRecordCount: 0
            )
            let labels = address.split(separator: ".").map(String.init).map(DNSLabel.init)
            let question = QuestionSection(labels: labels, type: type, questionClass: .internet)
            let message = Message(
                header: header,
                questions: [question],
                answers: [],
                authorities: [],
                additionalData: []
            )

            return self.send(message)
        }
    }

    func send(_ message: Message, to address: SocketAddress? = nil) -> EventLoopFuture<Message> {
        let promise: EventLoopPromise<Message> = loop.makePromise()

        return loop.flatSubmit {
            self.dnsDecoder.messageCache.withLockedValue { cache in
                cache[message.header.id] = SentQuery(message: message, promise: promise)
            }
            self.channel.writeAndFlush(message, promise: nil)

            struct DNSTimeoutError: Error {}

            self.loop.scheduleTask(in: .seconds(30)) {
                promise.fail(DNSTimeoutError())
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
        self.sendQuery(forHost: host, type: .srv).map { message in
            message.answers.compactMap { answer in
                guard case .srv(let record) = answer else {
                    return nil
                }

                return record
            }
        }
    }
}

extension DNSClient {
    /// Request IPv4 inverse address (PTR records) from nameserver
    ///
    /// PTR Records are for mapping IP addresses to Internet domain names
    /// Reverse DNS is also used for functions such as:
    /// - Network troubleshooting and testing
    /// - Checking domain names for suspicious information, such as overly generic reverse DNS names, dialup users or dynamically-assigned addresses in an attempt to limit email spam
    /// - Screening spam/phishing groups who forge domain information
    /// - Data logging and analysis within web servers
    ///
    /// Background references:
    /// - Management Guidelines & Operational Requirements for the Address and Routing Parameter Area Domain ("arpa") [IETF RFC 3172](https://www.rfc-editor.org/rfc/rfc3172.html)
    /// - IANA [.ARPA Zone Management](https://www.iana.org/domains/arpa)
    /// - About reverse DNS at [ARIN](https://www.arin.net/resources/manage/reverse/)
    ///
    /// - Parameter address: IPv4 Address with four dotted decial unsigned integers between the values of 0...255
    /// - Returns: A future with the resource record containing a domain name associated with the IPv4 Address.
    public func ipv4InverseAddress(_ address: String) -> EventLoopFuture<[ResourceRecord<PTRRecord>]> {
        // A.B.C.D -> D.C.B.A.IN-ADDR.ARPA.
        let inAddrArpaDomain =
            address
            .split(separator: ".")
            .map(String.init)
            .reversed()
            .joined(separator: ".")
            .appending(".in-addr.arpa.")

        return self.sendQuery(forHost: inAddrArpaDomain, type: .ptr).map { message in
            message.answers.compactMap { answer in
                guard case .ptr(let record) = answer else { return nil }
                return record
            }
        }
    }

    /// Request IPv6 inverse address (PTR records) from nameserver
    ///
    ///  Inverse addressing queries use DNS PTR Records.
    ///  An IPv6 address "2001:503:c27::2:30" is transformed into an inverse domain, then DNS query performed to get associated domain name.
    ///  0.3.0.0.2.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.7.2.c.0.3.0.5.0.1.0.0.2.ip6.arpa    domainname = j.root-servers.net.
    ///
    /// - Parameter address: IPv6 Address in long or compressed zero format
    /// - Returns: A future with the resource record containing a domain name associated with the IPv6 Address.
    /// - Throws: IOError(errnoCode: EINVAL, reason: #function) , IOError(errnoCode: errno, reason: #function)
    public func ipv6InverseAddress(_ address: String) -> EventLoopFuture<[ResourceRecord<PTRRecord>]> {
        var ipv6Addr = in6_addr()

        let retval = withUnsafeMutablePointer(to: &ipv6Addr) {
            inet_pton(AF_INET6, address, UnsafeMutablePointer($0))
        }

        // If inet_pton fails, return a pre-failed future immediately.
        if retval == 0 {
            let error = IOError(errnoCode: EINVAL, reason: #function)
            return self.loop.makeFailedFuture(error)
        } else if retval == -1 {
            let error = IOError(errnoCode: errno, reason: #function)
            return self.loop.makeFailedFuture(error)
        }

        #if canImport(Glibc)
        let inAddrArpaDomain = String(
            format: "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            ipv6Addr.__in6_u.__u6_addr8.0,
            ipv6Addr.__in6_u.__u6_addr8.1,
            ipv6Addr.__in6_u.__u6_addr8.2,
            ipv6Addr.__in6_u.__u6_addr8.3,
            ipv6Addr.__in6_u.__u6_addr8.4,
            ipv6Addr.__in6_u.__u6_addr8.5,
            ipv6Addr.__in6_u.__u6_addr8.6,
            ipv6Addr.__in6_u.__u6_addr8.7,
            ipv6Addr.__in6_u.__u6_addr8.8,
            ipv6Addr.__in6_u.__u6_addr8.9,
            ipv6Addr.__in6_u.__u6_addr8.10,
            ipv6Addr.__in6_u.__u6_addr8.11,
            ipv6Addr.__in6_u.__u6_addr8.12,
            ipv6Addr.__in6_u.__u6_addr8.13,
            ipv6Addr.__in6_u.__u6_addr8.14,
            ipv6Addr.__in6_u.__u6_addr8.15
        ).reversed()
            .map { "\($0)" }
            .joined(separator: ".")
            .appending(".ip6.arpa.")

        #elseif canImport(Musl)
        let inAddrArpaDomain = String(
            format: "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            ipv6Addr.__in6_union.__s6_addr.0,
            ipv6Addr.__in6_union.__s6_addr.1,
            ipv6Addr.__in6_union.__s6_addr.2,
            ipv6Addr.__in6_union.__s6_addr.3,
            ipv6Addr.__in6_union.__s6_addr.4,
            ipv6Addr.__in6_union.__s6_addr.5,
            ipv6Addr.__in6_union.__s6_addr.6,
            ipv6Addr.__in6_union.__s6_addr.7,
            ipv6Addr.__in6_union.__s6_addr.8,
            ipv6Addr.__in6_union.__s6_addr.9,
            ipv6Addr.__in6_union.__s6_addr.10,
            ipv6Addr.__in6_union.__s6_addr.11,
            ipv6Addr.__in6_union.__s6_addr.12,
            ipv6Addr.__in6_union.__s6_addr.13,
            ipv6Addr.__in6_union.__s6_addr.14,
            ipv6Addr.__in6_union.__s6_addr.15
        ).reversed()
            .map { "\($0)" }
            .joined(separator: ".")
            .appending(".ip6.arpa.")
        #else
        let inAddrArpaDomain = String(
            format: "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            ipv6Addr.__u6_addr.__u6_addr8.0,
            ipv6Addr.__u6_addr.__u6_addr8.1,
            ipv6Addr.__u6_addr.__u6_addr8.2,
            ipv6Addr.__u6_addr.__u6_addr8.3,
            ipv6Addr.__u6_addr.__u6_addr8.4,
            ipv6Addr.__u6_addr.__u6_addr8.5,
            ipv6Addr.__u6_addr.__u6_addr8.6,
            ipv6Addr.__u6_addr.__u6_addr8.7,
            ipv6Addr.__u6_addr.__u6_addr8.8,
            ipv6Addr.__u6_addr.__u6_addr8.9,
            ipv6Addr.__u6_addr.__u6_addr8.10,
            ipv6Addr.__u6_addr.__u6_addr8.11,
            ipv6Addr.__u6_addr.__u6_addr8.12,
            ipv6Addr.__u6_addr.__u6_addr8.13,
            ipv6Addr.__u6_addr.__u6_addr8.14,
            ipv6Addr.__u6_addr.__u6_addr8.15
        ).reversed()
            .map { "\($0)" }
            .joined(separator: ".")
            .appending(".ip6.arpa.")
        #endif

        return self.sendQuery(forHost: inAddrArpaDomain, type: .ptr).map { message in
            message.answers.compactMap { answer in
                guard case .ptr(let record) = answer else { return nil }
                return record
            }
        }
    }
}
