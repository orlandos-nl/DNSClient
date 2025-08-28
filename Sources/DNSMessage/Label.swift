import Foundation
import NIOCore

/// A label in a DNS message. This is a single part of a domain name. For example, `google` is a label in `google.com`. Labels are limited to 63 bytes and are not null terminated.
public struct DNSLabel: ExpressibleByStringLiteral, Sendable {
    /// The length of the label. This is the number of bytes in the label.
    public let length: UInt8

    /// The bytes of the label. This is the actual label, not including the length byte. This is a maximum of 63 bytes and is not null terminated. This is the raw bytes of the label, not the UTF-8 representation.
    public let label: [UInt8]

    /// Creates a new label from the given string.
    public init(stringLiteral string: String) {
        self.init(bytes: Array(string.utf8))
    }

    /// Creates a new label from the given bytes.
    public init(bytes: [UInt8]) {
        assert(bytes.count < 64)

        self.label = bytes
        self.length = UInt8(bytes.count)
    }
}

extension Sequence where Element == DNSLabel {
    /// Converts a sequence of DNS labels to a string.
    public var string: String {
        self.compactMap { label in
            if let string = String(bytes: label.label, encoding: .utf8), string.count > 0 {
                return string
            }

            return nil
        }.joined(separator: ".")
    }
}

extension ByteBuffer {
    /// Either write label index or list of labelsf
    @discardableResult
    public mutating func writeCompressedLabels(_ labels: [DNSLabel], labelIndices: inout [String: UInt16]) -> Int {
        var written = 0
        var labels = labels
        while !labels.isEmpty {
            let label = labels.removeFirst()
            // use combined labels as a key for a position in the packet
            let key = labels.string
            // if position exists output position or'ed with 0xc000 and return
            if let labelIndex = labelIndices[key] {
                written += writeInteger(labelIndex | 0xc000)
                return written
            } else {
                // if no position exists for this combination of labels output the first label
                labelIndices[key] = numericCast(writerIndex)
                written += writeInteger(UInt8(label.label.count))
                written += writeBytes(label.label)
            }
        }
        // write end of labels
        written += writeInteger(UInt8(0))
        return written
    }

    /// write labels into DNS packet
    @discardableResult
    public mutating func writeLabels(_ labels: [DNSLabel]) -> Int {
        var written = 0
        for label in labels {
            written += writeInteger(UInt8(label.label.count))
            written += writeBytes(label.label)
        }

        return written
    }

    func labelsSize(_ labels: [DNSLabel]) -> Int {
        labels.reduce(0, { $0 + 2 + $1.label.count })
    }
}
