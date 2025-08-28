import Foundation
import NIOCore

/// A DNS label representing a single component of a domain name (e.g., 'google' in 'google.com').
/// Labels must be ASCII-encoded, non-empty, and at most 63 bytes long.
public struct DNSLabel: Sendable, CustomStringConvertible, Hashable {
    public internal(set) var bytes: [UInt8]
    private let label: String

    public var description: String {
        self.label
    }

    /// Creates a new label from a given String.
    /// String must only contain ASCII encoded characters and must not exceed 63 characters.
    public init(_ label: String) throws {
        try Self.validateLabel(label)
        self.bytes = Array(label.utf8)
        self.label = label
    }

    /// Creates a new label from the given bytes.
    public init(bytes: [UInt8]) throws {
        let label = String(decoding: bytes, as: UTF8.self)
        try self.init(label)
    }

    /// Returns a new DNS label with all characters converted to lowercase.
    /// DNS names are case-insensitive, so this is often used for comparison.
    public func toLowercase() -> DNSLabel {
        try! DNSLabel(self.label.lowercased())
    }

    private static func validateLabel(_ label: String) throws {
        guard label.isValidLabel else {
            if label.isEmpty {
                throw DNSMessageError.emptyLabel()
            } else if label.count >= 64 {
                throw DNSMessageError.labelTooLong(label.count)
            } else if !label.allSatisfy({ $0.isASCII }) {
                throw DNSMessageError.labelNotAsciiEncoded(label)
            } else {
                throw DNSMessageError.invalidLabelFormat(label)
            }
        }
    }
}

extension DNSLabel: Equatable {
    public static func == (lhs: DNSLabel, rhs: DNSLabel) -> Bool {
        lhs.toLowercase().bytes == rhs.toLowercase().bytes
    }
}

extension String {
    var isValidLabel: Bool {
        guard self.allSatisfy({ $0.isASCII }) else { return false }
        guard !self.isEmpty && self.count < 64 else { return false }

        let firstChar = self.first!
        guard firstChar.isLetter || firstChar.isNumber || firstChar == "_" else { return false }

        guard self.count == 1 || self.last!.isLetter || self.last!.isNumber else { return false }

        let middleChars = self.dropFirst().dropLast()
        return middleChars.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
    }
}
