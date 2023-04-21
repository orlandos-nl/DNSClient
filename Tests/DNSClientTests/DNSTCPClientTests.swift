import XCTest
import NIO
@testable import DNSClient

final class DNSTCPClientTests: XCTestCase {
    var group: MultiThreadedEventLoopGroup!
    var dnsClient: DNSClient!
    
    override func setUp() {
        super.setUp()
        do {
            group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            dnsClient = try DNSClient.connectTCP(on: group, host: "8.8.8.8").wait()
        } catch let error {
            XCTFail("\(error)")
        }
    }
    
    func testStringAddress() throws {
        var buffer = ByteBuffer()
        buffer.writeInteger(0x7F000001 as UInt32)
        guard let record = ARecord.read(from: &buffer, length: buffer.readableBytes) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(record.stringAddress, "127.0.0.1")
    }
    
    func testStringAddressAAAA() throws {
        var buffer = ByteBuffer()
        buffer.writeBytes([0x2a, 0x00, 0x14, 0x50, 0x40, 0x01, 0x08, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x0e] as [UInt8])
        
        guard let record = AAAARecord.read(from: &buffer, length: buffer.readableBytes) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(record.stringAddress, "2a00:1450:4001:0809:0000:0000:0000:200e")
    }
    
    func testAQuery() throws {
        let results = try dnsClient.initiateAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
    }

    // Test that we can resolve a domain name to an IPv6 address
    func testAAAAQuery() throws {
        let results = try dnsClient.initiateAAAAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
    }

    // Given a domain name, test that we can resolve it to an IPv4 address
    func testSendQueryA() throws {
        let result = try dnsClient.sendQuery(forHost: "google.com", type: .a).wait()
        XCTAssertGreaterThanOrEqual(result.header.answerCount, 1, "The returned answers should be greater than or equal to 1")
    }

    // Test that we can resolve example.com to an IPv6 address
    func testResolveExampleCom() throws {
        let result = try dnsClient.sendQuery(forHost: "example.com", type: .aaaa).wait()
        XCTAssertGreaterThanOrEqual(result.header.answerCount, 1, "The returned answers should be greater than or equal to 1")
    }
    
    func testSendTxtQuery() throws {
        let result = try dnsClient.sendQuery(forHost: "google.com", type: .txt).wait()
        XCTAssertGreaterThanOrEqual(result.header.answerCount, 1, "The returned answers should be greater than or equal to 1")
    }
    
    func testSendQueryMX() throws {
        let result = try dnsClient.sendQuery(forHost: "gmail.com", type: .mx).wait()
        XCTAssertGreaterThanOrEqual(result.header.answerCount, 1, "The returned answers should be greater than or equal to 1")
    }

    func testSendQueryCNAME() throws {
        let result = try dnsClient.sendQuery(forHost: "www.youtube.com", type: .cName).wait()
        XCTAssertGreaterThanOrEqual(result.header.answerCount, 1, "The returned answers should be greater than or equal to 1")
    }

    func testSRVRecords() throws {
        let answers = try dnsClient.getSRVRecords(from: "_mongodb._tcp.ok0-xkvc1.mongodb.net").wait()
        XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
    }
    
    func testSRVRecordsAsyncRequest() throws {
        let expectation = self.expectation(description: "getSRVRecords")
        
        dnsClient.getSRVRecords(from: "_mongodb._tcp.ok0-xkvc1.mongodb.net")
            .whenComplete { (result) in
                switch result {
                case .failure(let error):
                    XCTFail("\(error)")
                case .success(let answers):
                    print(answers)
                    XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
                }
                expectation.fulfill()
            }
        self.waitForExpectations(timeout: 5, handler: nil)
    }
    
//    func testMulticastDNS() async throws {
//        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//        let client = try await DNSClient.connectMulticast(on: eventLoopGroup).get()
//        let addresses = try await client.sendQuery(
//            forHost: "my-host.local",
//            type: .any
//        ).get()
//        print(addresses)
//    }
    
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
