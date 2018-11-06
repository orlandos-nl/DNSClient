import XCTest
import NIO
@testable import NioDNS

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

    func testSendMessage() throws {
        let result = try dnsClient.sendMessage(to: "google.com", type: .aaaa).wait()
        XCTAssertGreaterThan(result.answers.count, 0, "There should atleast be 1 answer")
    }

    func testSRVRecords() throws {
        let answers = try dnsClient.getSRVRecords(from: "ok0-xkvc1.mongodb.net").wait()
        XCTAssertGreaterThan(answers.count, 0, "There should atleast be 1 answer")
    }

    static var allTests = [
        ("testSendMessage", testSendMessage),
        ("testSRVRecords", testSRVRecords),
    ]
}
