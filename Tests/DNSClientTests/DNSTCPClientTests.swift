import Testing
import NIO
@testable import DNSClient

#if canImport(Network)
import NIOTransportServices
#endif

@Suite("DNS TCP Client Tests")
struct DNSTCPClientTests {

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
        try await withTCPClients { dnsClient in
            let results = try await dnsClient.initiateAQuery(host: "google.com", port: 443).get()
            #expect(results.count >= 1, "The returned result should be greater than or equal to 1")
        }
    }

    @Test("AAAA Query")
    func aaaaQuery() async throws {
        try await withTCPClients { dnsClient in
            let results = try await dnsClient.initiateAAAAQuery(host: "google.com", port: 443).get()
            #expect(results.count >= 1, "The returned result should be greater than or equal to 1")
        }
    }

    @Test("Send A Query")
    func sendQueryA() async throws {
        try await withTCPClients { dnsClient in
            let result = try await dnsClient.sendQuery(forHost: "google.com", type: .a).get()
            #expect(result.header.answerCount >= 1, "The returned answers should be greater than or equal to 1")
        }
    }

    @Test("Resolve example.com to IPv6")
    func resolveExampleCom() async throws {
        try await withTCPClients { dnsClient in
            let result = try await dnsClient.sendQuery(forHost: "example.com", type: .aaaa).get()
            #expect(result.header.answerCount >= 1, "The returned answers should be greater than or equal to 1")
        }
    }

    @Test("Send TXT Query")
    func sendTxtQuery() async throws {
        try await withTCPClients { dnsClient in
            let result = try await dnsClient.sendQuery(forHost: "google.com", type: .txt).get()
            #expect(result.header.answerCount >= 1, "The returned answers should be greater than or equal to 1")
        }
    }

    @Test("Send MX Query")
    func sendQueryMX() async throws {
        try await withTCPClients { dnsClient in
            let result = try await dnsClient.sendQuery(forHost: "gmail.com", type: .mx).get()
            #expect(result.header.answerCount >= 1, "The returned answers should be greater than or equal to 1")
        }
    }

    @Test("Send CNAME Query")
    func sendQueryCNAME() async throws {
        try await withTCPClients { dnsClient in
            let result = try await dnsClient.sendQuery(forHost: "www.youtube.com", type: .cName).get()
            #expect(result.header.answerCount >= 1, "The returned answers should be greater than or equal to 1")
        }
    }

    @Test("SRV Records")
    func srvRecords() async throws {
        try await withTCPClients { dnsClient in
            let answers = try await dnsClient.getSRVRecords(from: "_caldavs._tcp.google.com").get()
            #expect(answers.count >= 1, "The returned answers should be greater than or equal to 1")
        }
    }

    @Test("Thread Safety")
    func threadSafety() async throws {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let client = try await DNSClient.connectTCP(
            on: eventLoopGroup.next(),
            host: "8.8.8.8"
        ).get()
        let hostname = "google.com"
        async let result = client.initiateAAAAQuery(host: hostname, port: 0).get()
        async let result2 = client.initiateAAAAQuery(host: hostname, port: 0).get()
        async let result3 = client.initiateAAAAQuery(host: hostname, port: 0).get()

        _ = try await [result, result2, result3]

        try await client.close().get()
        try await eventLoopGroup.shutdownGracefully()
    }
}

// MARK: - Helpers

private func withTCPClients(_ perform: (DNSClient) async throws -> Void) async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let dnsClient = try await DNSClient.connectTCP(on: group, host: "8.8.8.8").get()
    try await perform(dnsClient)
    try await dnsClient.close().get()
    try await group.shutdownGracefully()

    #if canImport(Network)
    let nwGroup = NIOTSEventLoopGroup(loopCount: 1)

    let nwDnsClient = try await DNSClient.connectTSTCP(on: nwGroup, host: "8.8.8.8").get()
    try await perform(nwDnsClient)
    try await nwDnsClient.close().get()
    try await nwGroup.shutdownGracefully()
    #endif
}
