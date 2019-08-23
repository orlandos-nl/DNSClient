import XCTest
import NIO
import DNSClient

final class DNSClientTests: XCTestCase {
    var group: MultiThreadedEventLoopGroup!
    var dnsClient: DNSClient!

    override func setUp() {
        super.setUp()
        do {
            group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            dnsClient = try DNSClient.connect(on: group, host: "8.8.8.8").wait()
        } catch let error {
            XCTFail("\(error)")
        }
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

    static var allTests = [
        ("testAQuery", testAQuery),
        ("testAAAAQuery", testAAAAQuery),
        ("testSendQuery", testSendQuery),
        ("testSRVRecords", testSRVRecords),
    ]
}
