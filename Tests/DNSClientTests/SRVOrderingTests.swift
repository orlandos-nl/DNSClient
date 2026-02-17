import XCTest

#if canImport(Network)
import NIOTransportServices
#endif
@testable import DNSClient

// Deterministic RNG that always returns 0
private struct ZeroRNG: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
}

// Deterministic RNG that always returns the maximum value.
private struct MaxRNG: RandomNumberGenerator {
    mutating func next() -> UInt64 { UInt64.max }
}

// Helper to build DNS labels from strings
private func labels(_ parts: [String]) -> [DNSLabel] {
    parts.map { DNSLabel(stringLiteral: $0) }
}

final class SRVOrderingTests: XCTestCase {
    func testPriorityOrdering() {
        // Mixed priorities; lower priority (0) must come first regardless of weights.
        let owner = labels(["service", "_tcp", "example", "com", ""]) // arbitrary
        func rec(priority: UInt16, weight: UInt16, target: String) -> ResourceRecord<SRVRecord> {
            let r = SRVRecord(priority: priority, weight: weight, port: 1, domainName: labels([target, "example", "com", ""]))
            return ResourceRecord(domainName: owner, dataType: 33, dataClass: 1, ttl: 60, resource: r)
        }
        let records: [ResourceRecord<SRVRecord>] = [
            rec(priority: 10, weight: 1, target: "hi1"),
            rec(priority: 0,  weight: 1, target: "lo1"),
            rec(priority: 10, weight: 1, target: "hi2"),
            rec(priority: 0,  weight: 1, target: "lo2"),
        ]

        var rng = ZeroRNG()
        let ordered = rfc2782Order(records, rng: &rng)
        let priorities = ordered.map { Int($0.resource.priority) }

        // Expect all 0s before any 10s.
        XCTAssertEqual(priorities.prefix(2), [0, 0])
        XCTAssertEqual(priorities.suffix(2), [10, 10])
    }

    func testWeightedSelectionAllowsZeroWeightWhenMixed() {
        // Same priority, weights: 5, 0. With RFC 2782 inclusive [0, S] selection and
        // zero-weight-first ordering, ZeroRNG (R=0) can select the zero-weight record.
        let owner = labels(["service", "_tcp", "example", "com", ""]) // arbitrary
        func rec(weight: UInt16, target: String) -> ResourceRecord<SRVRecord> {
            let r = SRVRecord(priority: 0, weight: weight, port: 1, domainName: labels([target, "example", "com", ""]))
            return ResourceRecord(domainName: owner, dataType: 33, dataClass: 1, ttl: 60, resource: r)
        }
        let records: [ResourceRecord<SRVRecord>] = [
            rec(weight: 5, target: "b"),
            rec(weight: 0, target: "a"),
        ]

        var rng = ZeroRNG()
        let ordered = rfc2782Order(records, rng: &rng)
        XCTAssertEqual(ordered.first?.resource.domainName.string, "a.example.com")
    }

    func testWeightedSelectionCanStillSelectPositiveWeight() {
        // Same priority, weights: 0, 5, 0. With MaxRNG (R=S), the positive-weight
        // record should be selected first.
        let owner = labels(["service", "_tcp", "example", "com", ""]) // arbitrary
        func rec(weight: UInt16, target: String) -> ResourceRecord<SRVRecord> {
            let r = SRVRecord(priority: 0, weight: weight, port: 1, domainName: labels([target, "example", "com", ""]))
            return ResourceRecord(domainName: owner, dataType: 33, dataClass: 1, ttl: 60, resource: r)
        }
        let records: [ResourceRecord<SRVRecord>] = [
            rec(weight: 0, target: "a"),
            rec(weight: 5, target: "b"),
            rec(weight: 0, target: "c"),
        ]

        var rng = MaxRNG()
        let ordered = rfc2782Order(records, rng: &rng)
        XCTAssertEqual(ordered.first?.resource.domainName.string, "b.example.com")
    }

    func testAllZeroWeightsProducesPermutation() {
        // All zero weights: selection is uniform random; with ZeroRNG it will pick index 0 repeatedly.
        let owner = labels(["service", "_tcp", "example", "com", ""]) // arbitrary
        func rec(target: String) -> ResourceRecord<SRVRecord> {
            let r = SRVRecord(priority: 0, weight: 0, port: 1, domainName: labels([target, "example", "com", ""]))
            return ResourceRecord(domainName: owner, dataType: 33, dataClass: 1, ttl: 60, resource: r)
        }
        let records: [ResourceRecord<SRVRecord>] = [
            rec(target: "a"),
            rec(target: "b"),
            rec(target: "c"),
        ]

        var rng = ZeroRNG()
        let ordered = rfc2782Order(records, rng: &rng)

        // Verify it's a permutation of inputs.
        XCTAssertEqual(Set(records.map { $0.resource.domainName.string }), Set(ordered.map { $0.resource.domainName.string }))
        XCTAssertEqual(records.count, ordered.count)
    }
}

final class SRVResourceRecordOrderingTests: XCTestCase {
    func testRFC2782Ordering_MirrorsDigExample() {
        // Mirror: _xmpp-client._tcp.conversations.im SRV
        // 5 0 5222 xmpp.conversations.im.
        // 10 0 80  xmpps.conversations.im.

        let owner = labels(["_xmpp-client", "_tcp", "conversations", "im", ""]) // owner name

        let r1 = SRVRecord(priority: 5,
                           weight: 0,
                           port: 5222,
                           domainName: labels(["xmpp", "conversations", "im", ""]))
        let rr1 = ResourceRecord(domainName: owner,
                                 dataType: 33, // SRV
                                 dataClass: 1, // IN
                                 ttl: 3600,
                                 resource: r1)

        let r2 = SRVRecord(priority: 10,
                           weight: 0,
                           port: 80,
                           domainName: labels(["xmpps", "conversations", "im", ""]))
        let rr2 = ResourceRecord(domainName: owner,
                                 dataType: 33,
                                 dataClass: 1,
                                 ttl: 3600,
                                 resource: r2)

        let ordered = rfc2782Order([rr2, rr1]) // intentionally out of order

        XCTAssertEqual(ordered.count, 2)
        XCTAssertEqual(ordered[0].resource.priority, 5)
        XCTAssertEqual(ordered[0].resource.port, 5222)
        XCTAssertEqual(ordered[0].resource.domainName.string, "xmpp.conversations.im")

        XCTAssertEqual(ordered[1].resource.priority, 10)
        XCTAssertEqual(ordered[1].resource.port, 80)
        XCTAssertEqual(ordered[1].resource.domainName.string, "xmpps.conversations.im")
    }
}
