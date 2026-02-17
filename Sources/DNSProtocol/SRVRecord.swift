import NIO

// RFC notes:
// - This implementation follows RFC 2782 selection semantics (priority grouping + weighted selection),
//   dot-target handling, Additional A/AAAA consumption, and fallback A/AAAA lookups via resolveSRV.
// - RFC 6335 and RFC 8553 update SRV naming/registration guidance (service/protocol label conventions),
//   but do not introduce new resolver-side requirements. We accept underscored labels as-is.

/// A DNS SRV record. This is used to specify the location of a service.
public struct SRVRecord: DNSResource {
    /// The priority of this record. Lower values are preferred. This is used to balance load between multiple servers. If two records have the same priority, the weight is used to balance load.
    public let priority: UInt16

    /// The weight of this record. Higher values are preferred. This is used to balance load between multiple servers. If two records have the same priority, the weight is used to balance load.
    public let weight: UInt16

    /// The port of the service.
    public let port: UInt16

    /// The domain name of the service. This can be used to resolve the IP address of the service.
    public let domainName: [DNSLabel]

    public init(priority: UInt16, weight: UInt16, port: UInt16, domainName: [DNSLabel]) {
        self.priority = priority
        self.weight = weight
        self.port = port
        self.domainName = domainName
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> SRVRecord? {
        guard
            let priority = buffer.readInteger(endianness: .big, as: UInt16.self),
            let weight = buffer.readInteger(endianness: .big, as: UInt16.self),
            let port = buffer.readInteger(endianness: .big, as: UInt16.self),
            let domainName = buffer.readLabels()
        else {
            return nil
        }

        return SRVRecord(priority: priority, weight: weight, port: port, domainName: domainName)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        var length = buffer.writeInteger(priority)
        length += buffer.writeInteger(weight)
        length += buffer.writeInteger(port)
        return length + buffer.writeCompressedLabels(domainName, labelIndices: &labelIndices)
    }
}

/// A resolved SRV target with its associated addresses.
///
/// This is returned by `DNSClient.resolveSRV(from:)` and preserves the RFC 2782
/// ordering of the underlying SRV records.
public struct SRVResolved: Sendable {
    /// The original SRV resource record.
    public let record: ResourceRecord<SRVRecord>

    /// The resolved addresses for the SRV target. Each address uses the SRV record’s port.
    public let addresses: [SocketAddress]

    /// True when the addresses were satisfied entirely from the DNS Additional section.
    public let fromAdditional: Bool

    /// Package-visible initializer so `DNSClient` can construct results while
    /// keeping external construction restricted.
    package init(
        record: ResourceRecord<SRVRecord>,
        addresses: [SocketAddress],
        fromAdditional: Bool
    ) {
        self.record = record
        self.addresses = addresses
        self.fromAdditional = fromAdditional
    }
}

/// Errors emitted by `srvConnect(from:connector:)`.
public enum SRVError: Error {
    /// A single SRV record with target "." indicates the service is unavailable.
    case serviceUnavailable

    /// No usable SRV records or addresses were available.
    case noRecords

    /// Connection attempts failed for all resolved addresses.
    case connectFailed(lastError: Error)
}

// MARK: - RFC 2782 ordering for DNSClient ResourceRecord<SRVRecord>

/// RFC 2782 ordering directly on DNSClient's SRV resource records.
/// 
/// Implements RFC 2782 Section 3 (Selection of SRV RR):
/// - Partition records by `priority` and process priorities in ascending order.
/// - For a given priority group, repeat until the group is empty:
///   - Let S be the sum of all `weight` values (weights ≤ 0 are treated as 0).
///   - If S == 0, select one record uniformly at random from the remaining set.
///   - Else, move all zero-weight records to the front (RFC 2782) and choose a
///     random number R in [0, S] (inclusive). Walk the set with cumulative sum
///     and select the first record where cumulative sum is >= R.
///   - Remove the selected record from the group and continue.
/// 
/// The resulting concatenation of all groups is the recommended connection
/// attempt order for the client.
///
/// - Parameters:
///   - records: The SRV resource records to order.
///   - rng: The random number generator used for the weighted selection within
///          a priority group.
/// - Returns: The input records ordered according to RFC 2782 selection rules.
/// - Complexity: O(n²) per priority group, suitable for typical SRV set sizes.
/// - Note: Package-visible for cross-target reuse by the `DNSClient` target.
package func rfc2782Order<RNG: RandomNumberGenerator>(_ records: [ResourceRecord<SRVRecord>], rng: inout RNG) -> [ResourceRecord<SRVRecord>] {
    // Group by priority (lowest first)
    let byPriority = Dictionary(grouping: records, by: { Int($0.resource.priority) }).sorted { $0.key < $1.key }

    var result: [ResourceRecord<SRVRecord>] = []
    for (_, group) in byPriority {
        // Work on a mutable copy of this priority group.
        var pool = group
        // Repeatedly select one target by weight until the group is exhausted.
        while !pool.isEmpty {
            // Recompute S (sum of weights) after each removal, per RFC.
            let totalWeight = pool.reduce(0) { $0 + max(0, Int($1.resource.weight)) }
            let chosenIndex: Int
            if totalWeight == 0 {
                // All weights are zero: uniform random choice among remaining records.
                chosenIndex = randomBelow(pool.count, using: &rng)
            } else {
                // RFC 2782: place zero-weight entries first so they have a small but
                // non-zero chance when R == 0.
                var selectionOrder: [Int] = []
                selectionOrder.reserveCapacity(pool.count)
                for index in pool.indices where pool[index].resource.weight == 0 {
                    selectionOrder.append(index)
                }
                for index in pool.indices where pool[index].resource.weight != 0 {
                    selectionOrder.append(index)
                }

                // Draw R in [0, S] inclusive and choose first cumulative >= R.
                let threshold = randomInclusive(totalWeight, using: &rng)
                var cumulative = 0
                var selected = selectionOrder[selectionOrder.count - 1]
                for index in selectionOrder {
                    cumulative += max(0, Int(pool[index].resource.weight))
                    if cumulative >= threshold {
                        selected = index
                        break
                    }
                }
                chosenIndex = selected
            }
            result.append(pool.remove(at: chosenIndex))
        }
    }
    return result
}

/// Convenience overload using `SystemRandomNumberGenerator`.
///
/// - Parameter records: The SRV resource records to order.
/// - Returns: The input records ordered according to RFC 2782 selection rules.
/// - Note: Package-visible for cross-target reuse by the `DNSClient` target.
package func rfc2782Order(_ records: [ResourceRecord<SRVRecord>]) -> [ResourceRecord<SRVRecord>] {
    var rng = SystemRandomNumberGenerator()
    return rfc2782Order(records, rng: &rng)
}

@inline(__always)
private func randomBelow<RNG: RandomNumberGenerator>(_ upper: Int, using rng: inout RNG) -> Int {
    precondition(upper > 0)
    let upperU64 = UInt64(upper)
    let randomValue = rng.next()
    // Use high 64-bits of 128-bit product for unbiased scaling without loops.
    let scaled = randomValue.multipliedFullWidth(by: upperU64).high
    return Int(truncatingIfNeeded: scaled)
}

@inline(__always)
private func randomInclusive<RNG: RandomNumberGenerator>(_ upperInclusive: Int, using rng: inout RNG) -> Int {
    precondition(upperInclusive >= 0 && upperInclusive < Int.max)
    return randomBelow(upperInclusive + 1, using: &rng)
}

// MARK: - RFC 2782 dot-target handling

/// Returns true when the labels represent the root target ("."), i.e. a single zero-length label.
internal func isRootTarget(_ labels: [DNSLabel]) -> Bool {
    return labels.count == 1 && labels[0].length == 0
}

/// Normalized domain name for comparisons (DNS names are case-insensitive).
///
/// - Note: Package-visible for cross-target reuse by the `DNSClient` target.
@inline(__always)
package func normalizedDomainName(_ labels: [DNSLabel]) -> String {
    return labels.string.lowercased()
}

/// Applies RFC 2782 "dot target" semantics:
/// - If there is exactly one SRV RR and its Target is ".", throw `SRVServiceUnavailable`.
/// - If multiple SRV RRs exist and some Targets are ".", drop those entries.
/// - Note: Package-visible for cross-target reuse by the `DNSClient` target.
package func applyDotTargetSemantics(
    _ records: [ResourceRecord<SRVRecord>]
) throws -> [ResourceRecord<SRVRecord>] {
    if records.count == 1, let record = records.first, isRootTarget(record.resource.domainName) {
        throw SRVServiceUnavailable()
    }
    return records.filter { !isRootTarget($0.resource.domainName) }
}

// MARK: - RFC 2782 Additional Data handling

/// - Note: Package-visible for cross-target reuse by the `DNSClient` target.
package struct SRVAdditionalInfo {
    package let addressesByTarget: [String: [String]]
    package let targetsNeedingLookup: [String]

    package init(addressesByTarget: [String: [String]], targetsNeedingLookup: [String]) {
        self.addressesByTarget = addressesByTarget
        self.targetsNeedingLookup = targetsNeedingLookup
    }
}

/// Extracts A/AAAA records from the Additional section, keyed by owner name.
internal func extractAdditionalAddresses(_ additionalRecords: [Record]) -> [String: [String]] {
    var result: [String: [String]] = [:]
    result.reserveCapacity(additionalRecords.count)

    for record in additionalRecords {
        switch record {
        case .a(let rr):
            let key = normalizedDomainName(rr.domainName)
            result[key, default: []].append(rr.resource.stringAddress)
        case .aaaa(let rr):
            let key = normalizedDomainName(rr.domainName)
            result[key, default: []].append(rr.resource.stringAddress)
        default:
            break
        }
    }

    return result
}

/// Builds a lookup plan for SRV targets using Additional A/AAAA records.
/// Targets present in `addressesByTarget` should not be re-queried.
/// - Note: Package-visible for cross-target reuse by the `DNSClient` target.
package func additionalInfoForSRVTargets(
    _ srvRecords: [ResourceRecord<SRVRecord>],
    additionalRecords: [Record]
) -> SRVAdditionalInfo {
    let addressesByTarget = extractAdditionalAddresses(additionalRecords)

    var missingTargets = Set<String>()
    missingTargets.reserveCapacity(srvRecords.count)
    for record in srvRecords {
        let target = normalizedDomainName(record.resource.domainName)
        if addressesByTarget[target]?.isEmpty != false {
            missingTargets.insert(target)
        }
    }

    return SRVAdditionalInfo(
        addressesByTarget: addressesByTarget,
        targetsNeedingLookup: Array(missingTargets)
    )
}

// MARK: - Array conveniences for RFC 2782 ordering

extension Array where Element == ResourceRecord<SRVRecord> {
    /// Returns a new array ordered per RFC 2782.
    ///
    /// The result is grouped by ascending `priority`; within a priority group,
    /// elements are ordered using weighted random selection. This overload uses
    /// `SystemRandomNumberGenerator` for the weighted selection.
    /// - Returns: A new array ordered according to RFC 2782 selection rules.
    internal func rfc2782Ordered() -> [Element] {
        rfc2782Order(self)
    }

    /// Returns a new array ordered per RFC 2782 using the provided RNG.
    ///
    /// The result is grouped by ascending `priority`; within a priority group,
    /// elements are ordered using weighted random selection.
    /// - Parameter rng: The random number generator used for weighted selection.
    ///                  The generator's state will be advanced.
    /// - Returns: A new array ordered according to RFC 2782 selection rules.
    internal func rfc2782Ordered<RNG: RandomNumberGenerator>(rng: inout RNG) -> [Element] {
        rfc2782Order(self, rng: &rng)
    }

    /// Orders this array in place per RFC 2782.
    ///
    /// The elements are grouped by ascending `priority`; within a priority group,
    /// elements are ordered using weighted random selection. This overload uses
    /// `SystemRandomNumberGenerator` for the weighted selection.
    internal mutating func rfc2782OrderInPlace() {
        self = rfc2782Order(self)
    }

    /// Orders this array in place per RFC 2782 using the provided RNG.
    ///
    /// The elements are grouped by ascending `priority`; within a priority group,
    /// elements are ordered using weighted random selection.
    /// - Parameter rng: The random number generator used for weighted selection.
    ///                  The generator's state will be advanced.
    internal mutating func rfc2782OrderInPlace<RNG: RandomNumberGenerator>(rng: inout RNG) {
        self = rfc2782Order(self, rng: &rng)
    }
}

// MARK: - EventLoopFuture convenience

extension EventLoopFuture where Value == [ResourceRecord<SRVRecord>] {
    /// Maps this future to RFC 2782–ordered results.
    ///
    /// The mapped value is grouped by ascending `priority`; within a priority group,
    /// elements are ordered using weighted random selection. This overload uses
    /// `SystemRandomNumberGenerator` for the weighted selection.
    internal func rfc2782Ordered() -> EventLoopFuture<Value> {
        self.map { records in rfc2782Order(records) }
    }

    /// Maps this future to RFC 2782–ordered results using the provided RNG.
    ///
    /// The mapping groups by ascending `priority` and applies weighted selection within
    /// each priority group. The `rng` is copied into the closure that performs the mapping.
    /// - Parameter rng: The random number generator used for weighted selection.
    /// - Returns: A future that succeeds with RFC 2782–ordered records.
    internal func rfc2782Ordered<RNG: RandomNumberGenerator & Sendable>(rng: RNG) -> EventLoopFuture<Value> {
        return self.map { records in
            var localRng = rng
            return rfc2782Order(records, rng: &localRng)
        }
    }
}
