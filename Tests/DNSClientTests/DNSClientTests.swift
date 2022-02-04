import XCTest
import NIO
import DNSClient

final class DNSClientTests: XCTestCase {
    var group: MultiThreadedEventLoopGroup!
    var dnsClient: DNSClient!

    override func setUp() async throws {
        super.setUp()
        dnsClient = try await DNSClient()
    }
    
    func testStringAddress() throws {
        var buffer = ByteBufferAllocator().buffer(capacity: 4)
        buffer.writeInteger(0x7F000001 as UInt32)
        guard let record = ARecord.read(from: &buffer, length: buffer.readableBytes) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(record.stringAddress, "127.0.0.1")
    }

    func testAQuery() throws {
        let results = try dnsClient.initiateAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
    }

    func testAAAAQuery() throws {
        let results = try dnsClient.initiateAAAAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
    }

    func testSendQuery() throws {
        let result = try dnsClient.sendQuery(forHost: "google.com", type: .txt).wait()
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

    static var allTests = [
        ("testAQuery", testAQuery),
        ("testAAAAQuery", testAAAAQuery),
        ("testSendQuery", testSendQuery),
        ("testSRVRecords", testSRVRecords),
    ]
}
