import XCTest
import NIO
import NioDNS

final class NioDNSTests: XCTestCase {
    var group: MultiThreadedEventLoopGroup!
    var dnsClient: NioDNS!

    override func setUp() {
        super.setUp()
        do {
            group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            dnsClient = try NioDNS.connect(on: group, host: "8.8.8.8").wait()
        } catch let error {
            print(error)
        }
    }

    func testAQuery() throws {
        let results = try dnsClient.initiateAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThan(results.count, 0, "The returned result should be greater than 0")
    }

    func testAAAAQuery() throws {
        let results = try dnsClient.initiateAAAAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThan(results.count, 0, "The returned result should be greater than 0")
    }

    func testSendQuery() throws {
        let result = try dnsClient.sendQuery(forHost: "google.com", type: .aaaa).wait()
        XCTAssertGreaterThan(result.answers.count, 0, "The returned answers should be greater than 0")
    }

    func testSRVRecords() throws {
        let answers = try dnsClient.getSRVRecords(from: "ok0-xkvc1.mongodb.net").wait()
        XCTAssertGreaterThan(answers.count, 0, "The returned answers should be greater than 0")
    }

    static var allTests = [
        ("testAQuery", testAQuery),
        ("testAAAAQuery", testAAAAQuery),
        ("testSendQuery", testSendQuery),
        ("testSRVRecords", testSRVRecords),
    ]
}
