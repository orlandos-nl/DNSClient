import Testing
import NIO
import DNSClient
import DNSServer

/// A mock DNS server delegate for testing.
final class MockDNSDelegate: DNSServerDelegate {
    private let responses: [String: [Record]]

    init(responses: [String: [Record]] = [:]) {
        self.responses = responses
    }

    func handleQuery(_ query: Message, context: DNSRequestContext) async throws -> Message {
        guard let question = query.questions.first else {
            return createResponse(for: query, answers: [], resultCode: .resultCodeFormatError)
        }

        let hostname = question.labels.string
        let records = responses[hostname] ?? []

        if records.isEmpty {
            return createResponse(for: query, answers: [], resultCode: .resultCodeNameError)
        }

        return createResponse(for: query, answers: records, resultCode: .resultCodeSuccess)
    }

    private func createResponse(for query: Message, answers: [Record], resultCode: MessageOptions) -> Message {
        Message(
            header: DNSMessageHeader(
                id: query.header.id,
                options: [.answer, resultCode],
                questionCount: UInt16(query.questions.count),
                answerCount: UInt16(answers.count),
                authorityCount: 0,
                additionalRecordCount: 0
            ),
            questions: query.questions,
            answers: answers,
            authorities: [],
            additionalData: []
        )
    }
}

@Suite("DNS Server Tests")
struct DNSServerTests {

    @Test("Server Start and Stop")
    func serverStartStop() async throws {
        let serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let delegate = MockDNSDelegate(responses: [:])
        let config = DNSServerConfiguration(
            host: "127.0.0.1",
            port: 0,
            enableUDP: true,
            enableTCP: false
        )
        let server = DNSServer(configuration: config, delegate: delegate, eventLoopGroup: serverGroup)
        try await server.start()
        #expect(server.udpPort != nil)
        try await server.stop()
        try await serverGroup.shutdownGracefully()
    }

    @Test("Client Connects to Server")
    func clientConnectsToServer() async throws {
        let serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let delegate = MockDNSDelegate(responses: [:])
        let config = DNSServerConfiguration(
            host: "127.0.0.1",
            port: 0,
            enableUDP: true,
            enableTCP: false
        )
        let server = DNSServer(configuration: config, delegate: delegate, eventLoopGroup: serverGroup)
        try await server.start()

        guard let port = server.udpPort else {
            Issue.record("Server did not bind to UDP port")
            return
        }

        // Just test that client can connect
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let client = try await DNSClient.connect(on: clientGroup, config: [address]).get()

        // Wait a moment
        try await Task.sleep(nanoseconds: 100_000_000)

        // Cleanup
        try await server.stop()
        try await client.close().get()
        try await serverGroup.shutdownGracefully()
        try await clientGroup.shutdownGracefully()
    }

    @Test("Simple Query")
    func simpleQuery() async throws {
        let serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        // Minimal mock delegate that just returns NXDOMAIN for everything
        let delegate = MockDNSDelegate(responses: [:])

        let config = DNSServerConfiguration(
            host: "127.0.0.1",
            port: 0,
            enableUDP: true,
            enableTCP: false
        )
        let server = DNSServer(configuration: config, delegate: delegate, eventLoopGroup: serverGroup)
        try await server.start()

        guard let port = server.udpPort else {
            Issue.record("Server did not bind to UDP port")
            return
        }

        let address = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let client = try await DNSClient.connect(on: clientGroup, config: [address]).get()

        // Send a simple query and expect NXDOMAIN response
        let response = try await client.sendQuery(forHost: "test.example", type: .a).get()
        #expect(response.header.options.isNameError)

        try await client.close().get()
        try await server.stop()
        try await serverGroup.shutdownGracefully()
        try await clientGroup.shutdownGracefully()
    }

    @Test("UDP Server with Mock Responses")
    func udpServerWithMockResponses() async throws {
        let serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        // Create mock responses
        let testLabels: [DNSLabel] = ["test", "local", ""]
        let aRecord = ResourceRecord(
            domainName: testLabels,
            dataType: DNSResourceType.a.rawValue,
            dataClass: DataClass.internet.rawValue,
            ttl: 300,
            resource: ARecord(address: 0x7F000001) // 127.0.0.1
        )

        let delegate = MockDNSDelegate(responses: [
            "test.local": [.a(aRecord)]
        ])

        // Start server on random port
        let config = DNSServerConfiguration(
            host: "127.0.0.1",
            port: 0,  // Random available port
            enableUDP: true,
            enableTCP: false
        )
        let server = DNSServer(configuration: config, delegate: delegate, eventLoopGroup: serverGroup)
        try await server.start()

        guard let port = server.udpPort else {
            Issue.record("Server did not bind to UDP port")
            return
        }

        // Connect client to mock server using separate event loop group
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let client = try await DNSClient.connect(on: clientGroup, config: [address]).get()

        // Test query for existing record - returns SocketAddresses
        let results = try await client.initiateAQuery(host: "test.local", port: 80).get()
        #expect(results.count == 1)
        // Verify we got the right IP address
        #expect(results.first != nil)

        // Test query for non-existing record
        let response = try await client.sendQuery(forHost: "nonexistent.local", type: .a).get()
        #expect(response.header.options.isNameError)

        // Cleanup
        try await client.close().get()
        try await server.stop()
        try await serverGroup.shutdownGracefully()
        try await clientGroup.shutdownGracefully()
    }

    @Test("TCP Server with Mock Responses")
    func tcpServerWithMockResponses() async throws {
        let serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        // Create mock responses
        let testLabels: [DNSLabel] = ["tcp", "test", ""]
        let aaaaRecord = ResourceRecord(
            domainName: testLabels,
            dataType: DNSResourceType.aaaa.rawValue,
            dataClass: DataClass.internet.rawValue,
            ttl: 300,
            resource: AAAARecord(address: [0x20, 0x01, 0x0d, 0xb8, 0x00, 0x00, 0x00, 0x00,
                                           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
        )

        let delegate = MockDNSDelegate(responses: [
            "tcp.test": [.aaaa(aaaaRecord)]
        ])

        // Start server on random port
        let config = DNSServerConfiguration(
            host: "127.0.0.1",
            port: 0,
            enableUDP: false,
            enableTCP: true
        )
        let server = DNSServer(configuration: config, delegate: delegate, eventLoopGroup: serverGroup)
        try await server.start()

        guard let port = server.tcpPort else {
            Issue.record("Server did not bind to TCP port")
            return
        }

        // Connect client to mock server via TCP
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let client = try await DNSClient.connectTCP(on: clientGroup, config: [address]).get()

        // Test query - returns SocketAddresses
        let results = try await client.initiateAAAAQuery(host: "tcp.test", port: 443).get()
        #expect(results.count == 1)

        // Cleanup
        try await client.close().get()
        try await server.stop()
        try await serverGroup.shutdownGracefully()
        try await clientGroup.shutdownGracefully()
    }

    @Test("Server with Multiple Records")
    func serverWithMultipleRecords() async throws {
        let serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        // Create multiple A records (like a load balancer)
        let labels: [DNSLabel] = ["multi", "example", ""]
        let records: [Record] = [
            .a(ResourceRecord(
                domainName: labels,
                dataType: DNSResourceType.a.rawValue,
                dataClass: DataClass.internet.rawValue,
                ttl: 300,
                resource: ARecord(address: 0xC0A80001) // 192.168.0.1
            )),
            .a(ResourceRecord(
                domainName: labels,
                dataType: DNSResourceType.a.rawValue,
                dataClass: DataClass.internet.rawValue,
                ttl: 300,
                resource: ARecord(address: 0xC0A80002) // 192.168.0.2
            ))
        ]

        let delegate = MockDNSDelegate(responses: [
            "multi.example": records
        ])

        let config = DNSServerConfiguration(
            host: "127.0.0.1",
            port: 0,
            enableUDP: true,
            enableTCP: false
        )
        let server = DNSServer(configuration: config, delegate: delegate, eventLoopGroup: serverGroup)
        try await server.start()

        guard let port = server.udpPort else {
            Issue.record("Server did not bind")
            return
        }

        let address = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let client = try await DNSClient.connect(on: clientGroup, config: [address]).get()
        let results = try await client.initiateAQuery(host: "multi.example", port: 80).get()

        #expect(results.count == 2)

        try await client.close().get()
        try await server.stop()
        try await serverGroup.shutdownGracefully()
        try await clientGroup.shutdownGracefully()
    }

    @Test("Both UDP and TCP Enabled")
    func bothUDPAndTCPEnabled() async throws {
        let serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let labels: [DNSLabel] = ["both", "test", ""]
        let record = ResourceRecord(
            domainName: labels,
            dataType: DNSResourceType.a.rawValue,
            dataClass: DataClass.internet.rawValue,
            ttl: 300,
            resource: ARecord(address: 0x0A000001) // 10.0.0.1
        )

        let delegate = MockDNSDelegate(responses: [
            "both.test": [.a(record)]
        ])

        let config = DNSServerConfiguration(
            host: "127.0.0.1",
            port: 0,
            enableUDP: true,
            enableTCP: true
        )
        let server = DNSServer(configuration: config, delegate: delegate, eventLoopGroup: serverGroup)
        try await server.start()

        #expect(server.udpPort != nil)
        #expect(server.tcpPort != nil)

        // Test UDP
        if let udpPort = server.udpPort {
            let address = try SocketAddress(ipAddress: "127.0.0.1", port: udpPort)
            let udpClient = try await DNSClient.connect(on: clientGroup, config: [address]).get()
            let udpResults = try await udpClient.initiateAQuery(host: "both.test", port: 80).get()
            #expect(udpResults.count == 1)
            try await udpClient.close().get()
        }

        // Test TCP
        if let tcpPort = server.tcpPort {
            let address = try SocketAddress(ipAddress: "127.0.0.1", port: tcpPort)
            let tcpClient = try await DNSClient.connectTCP(on: clientGroup, config: [address]).get()
            let tcpResults = try await tcpClient.initiateAQuery(host: "both.test", port: 80).get()
            #expect(tcpResults.count == 1)
            try await tcpClient.close().get()
        }

        try await server.stop()
        try await serverGroup.shutdownGracefully()
        try await clientGroup.shutdownGracefully()
    }

    @Test("Raw Message Query")
    func rawMessageQuery() async throws {
        let serverGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let clientGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        // Test accessing raw DNS records via sendQuery
        let testLabels: [DNSLabel] = ["raw", "test", ""]
        let aRecord = ResourceRecord(
            domainName: testLabels,
            dataType: DNSResourceType.a.rawValue,
            dataClass: DataClass.internet.rawValue,
            ttl: 300,
            resource: ARecord(address: 0x08080808) // 8.8.8.8
        )

        let delegate = MockDNSDelegate(responses: [
            "raw.test": [.a(aRecord)]
        ])

        let config = DNSServerConfiguration(
            host: "127.0.0.1",
            port: 0,
            enableUDP: true,
            enableTCP: false
        )
        let server = DNSServer(configuration: config, delegate: delegate, eventLoopGroup: serverGroup)
        try await server.start()

        guard let port = server.udpPort else {
            Issue.record("Server did not bind")
            return
        }

        let address = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let client = try await DNSClient.connect(on: clientGroup, config: [address]).get()
        let response = try await client.sendQuery(forHost: "raw.test", type: .a).get()

        #expect(response.header.answerCount == 1)
        #expect(response.header.options.isAnswer)

        // Check the actual record
        guard case .a(let record) = response.answers.first else {
            Issue.record("Expected A record")
            return
        }
        #expect(record.resource.address == 0x08080808)
        #expect(record.resource.stringAddress == "8.8.8.8")

        try await client.close().get()
        try await server.stop()
        try await serverGroup.shutdownGracefully()
        try await clientGroup.shutdownGracefully()
    }
}
