import XCTest

#if canImport(Network)
import NIOTransportServices
#endif
@testable import DNSClient

final class SRVDotTargetTests: XCTestCase {
    private func labels(_ parts: [String]) -> [DNSLabel] {
        parts.map { DNSLabel(stringLiteral: $0) }
    }

    private func makeRecord(targetLabels: [DNSLabel]) -> ResourceRecord<SRVRecord> {
        let owner = labels(["_service", "_tcp", "example", "com", ""])
        let record = SRVRecord(priority: 0, weight: 0, port: 80, domainName: targetLabels)
        return ResourceRecord(domainName: owner, dataType: 33, dataClass: 1, ttl: 60, resource: record)
    }

    func testSrvSingleDotTargetAborts() {
        let rootTarget = labels([""])
        let record = makeRecord(targetLabels: rootTarget)

        XCTAssertThrowsError(try applyDotTargetSemantics([record])) { error in
            XCTAssertNotNil(error as? SRVServiceUnavailable)
        }
    }

    func testSrvIgnoresDotAmongOthers() throws {
        let rootRecord = makeRecord(targetLabels: labels([""]))
        let normalRecord = makeRecord(targetLabels: labels(["srv", "example", "com", ""]))

        let filtered = try applyDotTargetSemantics([rootRecord, normalRecord])

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.resource.domainName.string, "srv.example.com")
    }
}
