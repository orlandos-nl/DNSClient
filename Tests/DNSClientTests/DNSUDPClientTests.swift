import Testing
import NIO
import DNSClient

#if canImport(Network)
import NIOTransportServices
#endif

@Suite("DNS UDP Client Tests")
struct DNSUDPClientTests {

    @Test("String address from ARecord")
    func stringAddress() throws {
        var buffer = ByteBuffer()
        buffer.writeInteger(0x7F000001 as UInt32)
        guard let record = ARecord.read(from: &buffer, length: buffer.readableBytes) else {
            Issue.record("Failed to read ARecord")
            return
        }

        #expect(record.stringAddress == "127.0.0.1")
    }

    @Test("String address from AAAARecord")
    func stringAddressAAAA() throws {
        var buffer = ByteBuffer()
        buffer.writeBytes([0x2a, 0x00, 0x14, 0x50, 0x40, 0x01, 0x08, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x0e] as [UInt8])

        guard let record = AAAARecord.read(from: &buffer, length: buffer.readableBytes) else {
            Issue.record("Failed to read AAAARecord")
            return
        }

        #expect(record.stringAddress == "2a00:1450:4001:0809:0000:0000:0000:200e")
    }

    @Test("A Query")
    func aQuery() async throws {
        try await withDNSClients { dnsClient in
            let results = try await dnsClient.initiateAQuery(host: "google.com", port: 443).get()
            #expect(results.count >= 1, "The returned result should be greater than or equal to 1")
        }
    }

    @Test("AAAA Query")
    func aaaaQuery() async throws {
        try await withDNSClients { dnsClient in
            let results = try await dnsClient.initiateAAAAQuery(host: "google.com", port: 443).get()
            #expect(results.count >= 1, "The returned result should be greater than or equal to 1")
        }
    }

    @Test("Send TXT Query")
    func sendTxtQuery() async throws {
        try await withDNSClients { dnsClient in
            let result = try await dnsClient.sendQuery(forHost: "google.com", type: .txt).get()
            #expect(result.header.answerCount == 0, "The returned answers should be 0 on UDP")
        }
    }

    @Test("Send MX Query")
    func sendQueryMX() async throws {
        try await withDNSClients { dnsClient in
            let result = try await dnsClient.sendQuery(forHost: "gmail.com", type: .mx).get()
            #expect(result.header.answerCount >= 1, "The returned answers should be greater than or equal to 1")
        }
    }

    @Test("Send CNAME Query")
    func sendQueryCNAME() async throws {
        try await withDNSClients { dnsClient in
            let result = try await dnsClient.sendQuery(forHost: "www.youtube.com", type: .cName).get()
            #expect(result.header.answerCount >= 1, "The returned answers should be greater than or equal to 1")
        }
    }

    @Test("SRV Records")
    func srvRecords() async throws {
        try await withDNSClients { dnsClient in
            let answers = try await dnsClient.getSRVRecords(from: "_caldavs._tcp.google.com").get()
            #expect(answers.count >= 1, "The returned answers should be greater than or equal to 1")
        }
    }

    @Test("NS Query")
    func nsQuery() async throws {
        try await withDNSClients { dnsClient in
            let results = try await dnsClient.initiateNSQuery(forDomain: "example.com").get()
            #expect(results.count == 2)
            let names = results.map { $0.resource.labels.string }.sorted()
            #expect(names == ["elliott.ns.cloudflare.com", "hera.ns.cloudflare.com"])
        }
    }

    @Test("SOA Query")
    func soaQuery() async throws {
        try await withDNSClients { dnsClient in
            let results = try await dnsClient.initiateSOAQuery(forDomain: "example.com").get()
            #expect(results.count == 1)
            #expect(results.first?.resource.mname.string == "elliott.ns.cloudflare.com")
        }
    }

    @Test("IPv4 Inverse Address")
    func ipv4InverseAddress() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let dnsClient = try await DNSClient.connect(on: group, host: "8.8.8.8").get()
        let answers = try await dnsClient.ipv4InverseAddress("8.8.4.4").get()

        #expect(answers.count >= 1, "The returned answers should be greater than or equal to 1")
        try await dnsClient.close().get()
        try await group.shutdownGracefully()
    }

    @Test("IPv4 Inverse Address with Multiple Responses")
    func ipv4InverseAddressMultipleResponses() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let dnsClient = try await DNSClient.connect(on: group, host: "8.8.8.8").get()
        let answers = try await dnsClient.ipv4InverseAddress("208.67.222.222").get()

        #expect(answers.count >= 1, "The returned answers should be greater than or equal to 1")
        try await dnsClient.close().get()
        try await group.shutdownGracefully()
    }

    @Test("IPv6 Inverse Address")
    func ipv6InverseAddress() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let dnsClient = try await DNSClient.connect(on: group, host: "8.8.8.8").get()
        // j.root-servers.net operated by Verisign, Inc.
        let answers = try await dnsClient.ipv6InverseAddress("2001:503:c27::2:30").get()

        #expect(answers.count >= 1, "The returned answers should be greater than or equal to 1")
        try await dnsClient.close().get()
        try await group.shutdownGracefully()
    }

    @Test("IPv6 Inverse Address with Invalid Input")
    func ipv6InverseAddressInvalidInput() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let dnsClient = try await DNSClient.connect(on: group, host: "8.8.8.8").get()

        await #expect(throws: (any Error).self) {
            _ = try await dnsClient.ipv6InverseAddress(":::0").get()
        }
        try await dnsClient.close().get()
        try await group.shutdownGracefully()
    }

    @Test("PTR Record Description")
    func ptrRecordDescription() {
        let domainname = PTRRecord(domainName: [DNSLabel(stringLiteral: "dns"),
                                               DNSLabel(stringLiteral: "google"),
                                               DNSLabel(stringLiteral: "")])

        #expect(domainname.description == "PTRRecord: dns.google")
    }
}

// MARK: - Helpers

private func withDNSClients(_ perform: (DNSClient) async throws -> Void) async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let dnsClient = try await DNSClient.connect(on: group, host: "8.8.8.8").get()
    try await perform(dnsClient)
    try await dnsClient.close().get()
    try await group.shutdownGracefully()

    #if canImport(Network)
    let nwGroup = NIOTSEventLoopGroup(loopCount: 1)

    let nwDnsClient = try await DNSClient.connectTS(on: nwGroup, host: "8.8.8.8").get()
    try await perform(nwDnsClient)
    try await nwDnsClient.close().get()
    try await nwGroup.shutdownGracefully()
    #endif
}
