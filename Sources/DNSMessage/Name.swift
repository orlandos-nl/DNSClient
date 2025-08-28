import Foundation
import NIOCore

public struct DNSName: CustomStringConvertible, Hashable, Sendable, Equatable {
    public internal(set) var labels: [DNSLabel]

    public var description: String {
        self.labels.map({ String(describing: $0) }).joined(separator: ".")
    }

    /// Total length in bytes including labels, separators, and terminating dot.
    public var length: Int {
        self.labels.reduce(0, { $0 + $1.bytes.count }) + self.labels.count + 1
    }

    /// Number of labels that make up this name
    public var count: Int {
        labels.count
    }

    public init(from: String) throws {
        self.labels = Array(try from.lazy.split(separator: ".").map({ try DNSLabel(String($0)) }))

        guard self.length <= 255 else {
            throw DNSMessageError.nameTooLong(self.length)
        }
    }

    /// Creates a DNS name from an array of labels.
    public init(labels: [DNSLabel]) throws {
        self.labels = labels

        guard self.length <= 255 else {
            throw DNSMessageError.nameTooLong(self.length)
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
        let newLength = self.length + Int(label.bytes.count) + 1
        guard newLength <= 255 else {
            throw DNSMessageError.nameTooLong(newLength)
        }

        labels.insert(label, at: index)
    }

    /// Append a DNS label to the end of this name.
    public mutating func append(label: DNSLabel) throws {
        try self.insert(label: label, at: self.labels.endIndex)
    }

    /// Appends another DNS name to this name.
    public mutating func append(contentsOf other: DNSName) throws {
        let newLength = self.length + other.length
        guard newLength <= 255 else {
            throw DNSMessageError.nameTooLong(newLength)
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
