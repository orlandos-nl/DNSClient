import DNSMessage
import NIO
import XCTest

@testable import DNSClient

#if canImport(Network)
import NIOTransportServices
#endif

final class DNSTCPClientTests: XCTestCase {
    var group: MultiThreadedEventLoopGroup!
    var dnsClient: DNSClient!

    #if canImport(Network)
    var nwGroup: NIOTSEventLoopGroup!
    var nwDnsClient: DNSClient!
    #endif

    override func setUpWithError() throws {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        dnsClient = try DNSClient.connectTCP(on: group, host: "8.8.8.8").wait()

        #if canImport(Network)
        nwGroup = NIOTSEventLoopGroup(loopCount: 1)
        nwDnsClient = try DNSClient.connectTSTCP(on: nwGroup, host: "8.8.8.8").wait()
        #endif
    }

    func testClient(_ perform: (DNSClient) throws -> Void) rethrows {
        try perform(dnsClient)
        #if canImport(Network)
        try perform(nwDnsClient)
        #endif
    }

    func testStringAddress() throws {
        var buffer = ByteBuffer()
        buffer.writeInteger(0x7F00_0001 as UInt32)
        guard let record = ARecord.read(from: &buffer, length: buffer.readableBytes) else {
            XCTFail()
            return
        }

        XCTAssertEqual(record.stringAddress, "127.0.0.1")
    }

    func testStringAddressAAAA() throws {
        var buffer = ByteBuffer()
        buffer.writeBytes(
            [0x2a, 0x00, 0x14, 0x50, 0x40, 0x01, 0x08, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x0e] as [UInt8]
        )

        guard let record = AAAARecord.read(from: &buffer, length: buffer.readableBytes) else {
            XCTFail()
            return
        }

        XCTAssertEqual(record.stringAddress, "2a00:1450:4001:0809:0000:0000:0000:200e")
    }

    func testAQuery() throws {
        try testClient { dnsClient in
            let results = try dnsClient.initiateAQuery(host: "google.com", port: 443).wait()
            XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
        }
    }

    // Test that we can resolve a domain name to an IPv6 address
    func testAAAAQuery() throws {
        try testClient { dnsClient in
            let results = try dnsClient.initiateAAAAQuery(host: "google.com", port: 443).wait()
            XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
        }
    }

    // Given a domain name, test that we can resolve it to an IPv4 address
    func testSendQueryA() throws {
        try testClient { dnsClient in
            let result = try dnsClient.sendQuery(forHost: "google.com", type: .a).wait()
            XCTAssertGreaterThanOrEqual(
                result.header.answerCount,
                1,
                "The returned answers should be greater than or equal to 1"
            )
        }
    }

    // Test that we can resolve example.com to an IPv6 address
    func testResolveExampleCom() throws {
        try testClient { dnsClient in
            let result = try dnsClient.sendQuery(forHost: "example.com", type: .aaaa).wait()
            XCTAssertGreaterThanOrEqual(
                result.header.answerCount,
                1,
                "The returned answers should be greater than or equal to 1"
            )
        }
    }

    func testSendTxtQuery() throws {
        try testClient { dnsClient in
            let result = try dnsClient.sendQuery(forHost: "google.com", type: .txt).wait()
            XCTAssertGreaterThanOrEqual(
                result.header.answerCount,
                1,
                "The returned answers should be greater than or equal to 1"
            )
        }
    }

    func testSendQueryMX() throws {
        try testClient { dnsClient in
            let result = try dnsClient.sendQuery(forHost: "gmail.com", type: .mx).wait()
            XCTAssertGreaterThanOrEqual(
                result.header.answerCount,
                1,
                "The returned answers should be greater than or equal to 1"
            )
        }
    }

    func testSendQueryCNAME() throws {
        try testClient { dnsClient in
            let result = try dnsClient.sendQuery(forHost: "www.youtube.com", type: .cName).wait()
            XCTAssertGreaterThanOrEqual(
                result.header.answerCount,
                1,
                "The returned answers should be greater than or equal to 1"
            )
        }
    }

    func testSRVRecords() throws {
        try testClient { dnsClient in
            let answers = try dnsClient.getSRVRecords(from: "_caldavs._tcp.google.com").wait()
            XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
        }
    }

    func testSRVRecordsAsyncRequest() throws {
        testClient { dnsClient in
            let expectation = self.expectation(description: "getSRVRecords")

            dnsClient.getSRVRecords(from: "_caldavs._tcp.google.com")
                .whenComplete { (result) in
                    switch result {
                    case .failure(let error):
                        XCTFail("\(error)")
                    case .success(let answers):
                        XCTAssertGreaterThanOrEqual(
                            answers.count,
                            1,
                            "The returned answers should be greater than or equal to 1"
                        )
                    }
                    expectation.fulfill()
                }
            self.waitForExpectations(timeout: 5, handler: nil)
        }
    }

    func testThreadSafety() async throws {
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

        try await client.channel.close(mode: .all).get()
    }

    func testAll() throws {
        try testSRVRecords()
        try testSRVRecordsAsyncRequest()
        try testSendQueryMX()
        try testSendQueryCNAME()
        try testSendTxtQuery()
        try testAQuery()
        try testAAAAQuery()
    }
}
