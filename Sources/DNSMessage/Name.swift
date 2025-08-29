import Foundation
import NIOCore

/// Represents a DNS domain name as a sequence of labels (e.g., "example.com" → ["example", "com"]).
public struct DNSName: CustomStringConvertible, Hashable, Sendable, Equatable {
    public internal(set) var labels: [DNSLabel]

    public var description: String {
        self.labels.map({ String(describing: $0) }).joined(separator: ".")
    }

    /// Total length in bytes including labels, separators, and terminating dot.
    public var characterCount: Int {
        self.labels.reduce(0, { $0 + $1.bytes.count }) + self.labels.count + 1
    }

    /// Number of labels that make up this name
    public var labelCount: Int {
        labels.count
    }

    /// Creates a DNS name from a dot-separated string (e.g., "example.com").
    /// Each component between dots becomes a DNS label with proper validation.
    public init(from: String) throws {
        self.labels = Array(try from.lazy.split(separator: ".").map({ try DNSLabel(String($0)) }))

        guard self.characterCount <= 255 else {
            throw DNSMessageError.nameTooLong(self.characterCount)
        }
    }

    /// Creates a DNS name from an array of labels.
    public init(labels: [DNSLabel]) throws {
        self.labels = labels

        guard self.characterCount <= 255 else {
            throw DNSMessageError.nameTooLong(self.characterCount)
        }
    }

    /// Create an empty DNS name
    public init() {
        self.labels = []
    }

    /// Turn this label into lowercase
    public mutating func toLowercase() {
        self.labels = Array(self.labels.lazy.map({ $0.toLowercase() }))
    }

    /// Insert a DNS label at any point inside this name
    public mutating func insert(label: DNSLabel, at index: Index) throws {
        let newCount = self.characterCount + Int(label.bytes.count) + 1
        guard newCount <= 255 else {
            throw DNSMessageError.nameTooLong(newCount)
        }

        labels.insert(label, at: index)
    }

    /// Append a DNS label to the end of this name.
    public mutating func append(label: DNSLabel) throws {
        try self.insert(label: label, at: self.labels.endIndex)
    }

    /// Appends another DNS name to this name.
    public mutating func append(contentsOf other: DNSName) throws {
        let newCount = self.characterCount + other.characterCount
        guard newCount <= 255 else {
            throw DNSMessageError.nameTooLong(newCount)
        }

        self.labels.append(contentsOf: other.labels)
    }

    /// Append a DNS label to the start of this name
    public mutating func prepend(label: DNSLabel) throws {
        try self.insert(label: label, at: self.labels.startIndex)
    }

    /// Remove the label at an index.
    public mutating func remove(at index: Index) -> DNSLabel {
        self.labels.remove(at: index)
    }

    /// Only used for subscript. So only used when we already have a valid DNSName.
    private init(uncheckedLabels: [DNSLabel]) {
        self.labels = uncheckedLabels
    }
}

extension DNSName: Collection {
    public typealias Index = Array<DNSLabel>.Index

    public var startIndex: Index {
        labels.startIndex
    }

    public var endIndex: Index {
        labels.endIndex
    }

    public func index(after i: Index) -> Index {
        labels.index(after: i)
    }

    public subscript(position: Index) -> DNSLabel {
        labels[position]
    }

    public subscript(bounds: Range<Index>) -> DNSName {
        DNSName(uncheckedLabels: Array(labels[bounds]))
    }

    public subscript<R>(bounds: R) -> DNSName where R: RangeExpression, R.Bound == Index {
        DNSName(uncheckedLabels: Array(labels[bounds]))
    }
}

/// Specifies how DNS names should be encoded in wire format.
///
/// The encoding strategy determines both compression behavior and case handling, which evolved
/// through multiple RFCs:
///
/// - RFC 1035: Introduced name compression for efficiency
/// - RFC 3597: Restricted compression for new record types
/// - RFC 3597 Section 7: Mandated lowercase conversion for DNSSEC canonical form
public struct DNSNameEncoding: Equatable, Comparable, Hashable, Sendable {
    public internal(set) var rawValue: UInt8

    /// Uses DNS compression with automatic lowercasing for DNSSEC canonical form.
    /// According to RFC 3597 Section 7, names are converted to lowercase when compressed to ensure
    /// DNSSEC signature correctness when case distinctions are lost due to compression.
    public static var compressed: Self { .init(rawValue: 0) }

    /// No compression, preserves original case of domain names.
    public static var uncompressed: Self { .init(rawValue: 1) }

    /// No compression, with explicit conversion to lowercase for canonical form.
    public static var uncompressedLowercase: Self { .init(rawValue: 2) }

    public static func < (lhs: DNSNameEncoding, rhs: DNSNameEncoding) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
