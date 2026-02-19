import XCTest
import NIO
import NIOEmbedded

#if canImport(Network)
import NIOTransportServices
#endif
@testable import DNSClient

final class SRVConnectTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case first
        case second
    }

    func testConnectInOrderSucceedsOnSecondAddress() throws {
        let loop = EmbeddedEventLoop()
        let addresses = [
            try SocketAddress(ipAddress: "127.0.0.1", port: 1),
            try SocketAddress(ipAddress: "127.0.0.1", port: 2)
        ]

        let future: EventLoopFuture<String> = DNSClient.connectInOrder(addresses: addresses, on: loop) { address in
            if address.port == 1 {
                return loop.makeFailedFuture(TestError.first)
            }
            return loop.makeSucceededFuture("ok")
        }

        XCTAssertEqual(try future.wait(), "ok")
    }

    func testConnectInOrderFailsWhenAllFail() throws {
        let loop = EmbeddedEventLoop()
        let addresses = [
            try SocketAddress(ipAddress: "127.0.0.1", port: 1),
            try SocketAddress(ipAddress: "127.0.0.1", port: 2)
        ]

        let future: EventLoopFuture<String> = DNSClient.connectInOrder(addresses: addresses, on: loop) { address in
            if address.port == 1 {
                return loop.makeFailedFuture(TestError.first)
            }
            return loop.makeFailedFuture(TestError.second)
        }

        XCTAssertThrowsError(try future.wait()) { error in
            guard let srvError = error as? SRVError else {
                XCTFail("Expected SRVError.connectFailed")
                return
            }
            guard case let .connectFailed(lastError) = srvError else {
                XCTFail("Expected SRVError.connectFailed")
                return
            }
            XCTAssertEqual(lastError as? TestError, .second)
        }
    }

    func testConnectInOrderNoRecords() throws {
        let loop = EmbeddedEventLoop()
        let future: EventLoopFuture<String> = DNSClient.connectInOrder(addresses: [], on: loop) { _ in
            loop.makeSucceededFuture("unused")
        }

        XCTAssertThrowsError(try future.wait()) { error in
            guard let srvError = error as? SRVError, case .noRecords = srvError else {
                XCTFail("Expected SRVError.noRecords")
                return
            }
        }
    }
}
