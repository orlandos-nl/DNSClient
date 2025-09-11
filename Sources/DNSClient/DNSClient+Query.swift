public import DNSMessage
import Foundation
public import NIO
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
            message.answers.compactMap { try? $0.rData(as: ARecord.self)?.socketAddress(port: port) }
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
            message.answers.compactMap { try? $0.rData(as: AAAARecord.self)?.socketAddress(port: port) }
        }
    }

    /// Cancel all queries that are currently running. This will fail all futures with a `CancelError`
    public func cancelQueries() {
        self.inboundHandler.messageCache.withLockedValue { cache in
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
        additionalOptions: DNSHeaderFlags? = nil,
        timeout: TimeAmount = .seconds(30)
    ) -> EventLoopFuture<DNSMessage> {
        let question = try? DNSQuestion(name: DNSName(from: address), type: type, questionClass: .internet)
        return channel.eventLoop.flatSubmit {
            let messageID = self.messageID.withLockedValue { id in
                let newID = id &+ 1
                id = newID
                return id
            }

            var options: DNSHeaderFlags = []

            if !self.isMulticast {
                options.insert(.recursionDesired)
            }

            if let additionalOptions = additionalOptions {
                options.insert(additionalOptions)
            }

            let header = DNSHeader(
                id: messageID,
                flags: options
            )
            var message = DNSMessage(
                header: header
            )

            if let question = question {
                message.questions.append(question)
            }

            return self.send(message, to: nil, timeout: timeout)
        }
    }

    // MARK: - Transport primitive (timeout-aware overload + wrapper)

    /// Historical behavior wrapper (30s default); forwards to timeout-aware overload.
    /// Keeping this avoids any source change for existing callers.
    func send(_ message: DNSMessage, to address: SocketAddress? = nil) -> EventLoopFuture<DNSMessage> {
        self.send(message, to: address, timeout: .seconds(30))
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
    func send(
        _ message: DNSMessage,
        to address: SocketAddress? = nil,
        timeout: TimeAmount
    ) -> EventLoopFuture<DNSMessage> {
        let promise: EventLoopPromise<DNSMessage> = loop.makePromise()

        return loop.flatSubmit {
            // Register in-flight
            self.inboundHandler.messageCache.withLockedValue { cache in
                cache[message.header.id] = SentQuery(message: message, promise: promise)
            }

            // Write on the channel
            self.channel.writeAndFlush(message, promise: nil)

            struct DNSTimeoutError: Error {}

            // Schedule a timeout that also removes the in-flight cache entry to avoid leaks
            let timeoutTask = self.loop.scheduleTask(in: timeout) { [messageCache = self.inboundHandler.messageCache] in
                messageCache.withLockedValue { cache in
                    cache[message.header.id] = nil
                }
                promise.fail(DNSTimeoutError())
            }

            // Ensure timer is cancelled once the promise resolves
            promise.futureResult.whenComplete { a in
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
    public func getSRVRecords(from host: String) -> EventLoopFuture<[DNSResourceRecord<SRVRecord>]> {
        self.sendQuery(forHost: host, type: .srv).map { message in
            message.answers.compactMap {
                $0.asResourceRecord(SRVRecord.self)
            }
        }
    }

    /// Request NS records for a domain
    ///
    /// - parameters:
    ///     - host: Hostname to get the records from
    /// - returns: A future with an array of resource records
    public func initiateNSQuery(forDomain domain: String) -> EventLoopFuture<[DNSResourceRecord<NSRecord>]> {
        self.sendQuery(forHost: domain, type: .ns).map { message in
            message.answers.compactMap {
                $0.asResourceRecord(NSRecord.self)
            }
        }
    }

    /// Request SOA records from a host
    ///
    /// - parameters:
    ///     - host: Hostname to get the records from
    /// - returns: A future with an array of resource records
    public func initiateSOAQuery(forDomain domain: String) -> EventLoopFuture<[DNSResourceRecord<SOARecord>]> {
        self.sendQuery(forHost: domain, type: .soa).map { message in
            message.answers.compactMap {
                $0.asResourceRecord(SOARecord.self)
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
    public func ipv4InverseAddress(_ address: String) -> EventLoopFuture<[DNSResourceRecord<PTRRecord>]> {
        // A.B.C.D -> D.C.B.A.IN-ADDR.ARPA.
        let inAddrArpaDomain =
            address
            .split(separator: ".")
            .map(String.init)
            .reversed()
            .joined(separator: ".")
            .appending(".in-addr.arpa.")

        return self.sendQuery(forHost: inAddrArpaDomain, type: .ptr).map { message in
            message.answers.compactMap {
                $0.asResourceRecord(PTRRecord.self)
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
    public func ipv6InverseAddress(_ address: String) -> EventLoopFuture<[DNSResourceRecord<PTRRecord>]> {
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
            message.answers.compactMap {
                $0.asResourceRecord(PTRRecord.self)
            }
        }
    }
}
