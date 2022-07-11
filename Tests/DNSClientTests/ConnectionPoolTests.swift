import XCTest
import NIO
@testable import DNSClient

final class ConnectionPoolTests: XCTestCase {
    var group: MultiThreadedEventLoopGroup!
    
    override func setUp() {
        super.setUp()
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }
    
    func testConnectionAsPool() throws {
        let dnsClient = try DNSClient.connectTCP(on: group, host: "8.8.8.8").wait()
        
        let results = try dnsClient.initiateAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
        let nextClient = try dnsClient.next(for: .init(protocolPreference: .tcp, host: "google.com", port: 443)).wait()
        let nextResult = try nextClient.initiateAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThanOrEqual(nextResult.count, 1, "The returned result should be greater than or equal to 1")
    }
    
    func testConnectionReuse() throws {
        let dnsConnectionPool = MultipleConnectionPool(on: group.next())
        
        let _ = try dnsConnectionPool.next(for: .init(host: "8.8.8.8")).wait()
        XCTAssertEqual(dnsConnectionPool.pool.count, 1)
        
        let _ = try dnsConnectionPool.next(for: .init(host: "8.8.8.8")).wait()
        XCTAssertEqual(dnsConnectionPool.pool.count, 1)
        
        let _ = try dnsConnectionPool.next(for: .init(protocolPreference: .tcp, host: "8.8.8.8")).wait()
        XCTAssertEqual(dnsConnectionPool.pool.count, 2)
    }
    
    func testUnpooledRequirement() throws {
        let dnsConnectionPool = MultipleConnectionPool(on: group.next())
        
        let _ = dnsConnectionPool.next(for: .init(sourcingPreference: .unpooled, host: "8.8.8.8"))
        XCTAssertEqual(dnsConnectionPool.pool.count, 0)
    }
    
    func testNewSourcing() throws {
        let dnsConnectionPool = MultipleConnectionPool(on: group.next())
        
        let _ = try dnsConnectionPool.next(for: .init(sourcingPreference: .new, host: "8.8.8.8")).wait()
        let _ = try dnsConnectionPool.next(for: .init(sourcingPreference: .new, host: "8.8.8.8")).wait()
        let _ = try dnsConnectionPool.next(for: .init(sourcingPreference: .new, host: "8.8.8.8")).wait()
        XCTAssertEqual(dnsConnectionPool.pool.count, 3)
    }
}
