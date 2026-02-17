import XCTest

#if canImport(Network)
import NIOTransportServices
#endif
@testable import DNSClient

final class SRVAdditionalDataTests: XCTestCase {
    private func labels(_ parts: [String]) -> [DNSLabel] {
        parts.map { DNSLabel(stringLiteral: $0) }
    }

    private func makeSRV(targetLabels: [DNSLabel]) -> ResourceRecord<SRVRecord> {
        let owner = labels(["_service", "_tcp", "example", "com", ""])
        let record = SRVRecord(priority: 0, weight: 0, port: 80, domainName: targetLabels)
        return ResourceRecord(domainName: owner, dataType: 33, dataClass: 1, ttl: 60, resource: record)
    }

    private func makeA(owner: [DNSLabel], address: UInt32) -> Record {
        let rr = ResourceRecord(domainName: owner, dataType: 1, dataClass: 1, ttl: 60, resource: ARecord(address: address))
        return .a(rr)
    }

    private func makeAAAA(owner: [DNSLabel], address: [UInt8]) -> Record {
        let rr = ResourceRecord(domainName: owner, dataType: 28, dataClass: 1, ttl: 60, resource: AAAARecord(address: address))
        return .aaaa(rr)
    }

    func testAdditionalDataMatchesSrvTargets() {
        let targetA = labels(["a", "example", "com", ""])
        let targetB = labels(["b", "example", "com", ""])
        let srvRecords = [makeSRV(targetLabels: targetA), makeSRV(targetLabels: targetB)]

        let additional: [Record] = [
            makeA(owner: targetA, address: 0x01020304), // 1.2.3.4
            makeAAAA(owner: targetB, address: [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
        ]

        let info = additionalInfoForSRVTargets(srvRecords, additionalRecords: additional)

        XCTAssertEqual(info.targetsNeedingLookup.count, 0)
        XCTAssertEqual(info.addressesByTarget["a.example.com"]?.first, "1.2.3.4")
        XCTAssertEqual(info.addressesByTarget["b.example.com"]?.first, "2001:0db8:0000:0000:0000:0000:0000:0001")
    }

    func testAdditionalDataOnlySatisfiesOneTarget() {
        let targetA = labels(["a", "example", "com", ""])
        let targetB = labels(["b", "example", "com", ""])
        let srvRecords = [makeSRV(targetLabels: targetA), makeSRV(targetLabels: targetB)]

        let additional: [Record] = [
            makeA(owner: targetA, address: 0x01020304) // 1.2.3.4
        ]

        let info = additionalInfoForSRVTargets(srvRecords, additionalRecords: additional)

        XCTAssertEqual(info.addressesByTarget["a.example.com"]?.count, 1)
        XCTAssertEqual(Set(info.targetsNeedingLookup), ["b.example.com"])
    }
}
