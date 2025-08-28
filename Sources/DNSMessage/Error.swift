import Foundation

/// Errors that can occur during DNS message parsing, validation, or construction.
public struct DNSMessageError: Error, Equatable, Hashable, Sendable {
    private var backing: Backing

    fileprivate init(backing: Backing) {
        self.backing = backing
    }

    /// The provided string is not ASCII encoded.
    /// - Parameter label: The label that is not ASCII encoded.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func labelNotAsciiEncoded(_ label: String) -> DNSMessageError {
        Self.init(backing: .labelNotAsciiEncoded(label))
    }

    /// A DNS label cannot be empty.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func emptyLabel() -> DNSMessageError {
        Self.init(backing: .emptyLabel)
    }

    /// A DNS label cannot exceed 63 bytes in length.
    /// - Parameter length: The length of the label that is too long.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func labelTooLong(_ length: Int) -> DNSMessageError {
        Self.init(backing: .labelTooLong(length))
    }

    /// A DNS label does not conform to RFC requirements.
    /// - Parameter label: The label that has an invalid format.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func invalidLabelFormat(_ label: String) -> DNSMessageError {
        Self.init(backing: .invalidLabelFormat(label))
    }

    /// A DNS name cannot exceed 255 bytes in total length.
    /// - Parameter length: The length of the name that is too long.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func nameTooLong(_ length: Int) -> DNSMessageError {
        Self.init(backing: .nameTooLong(length))
    }

    /// An unrecognized label code was encountered during DNS name parsing.
    /// - Parameter code: The unrecognized label code.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func unrecognizedLabelCode(_ code: UInt8) -> DNSMessageError {
        Self.init(backing: .unrecognizedLabelCode(code))
    }

    /// Insufficient data available for decoding.
    /// - Parameters:
    ///   - expected: The number of bytes expected.
    ///   - available: The number of bytes available.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func insufficientData(expected: Int, available: Int) -> DNSMessageError {
        Self.init(backing: .insufficientData(expected: expected, available: available))
    }

    /// Invalid format encountered during decoding.
    /// - Parameters:
    ///   - field: The field that has invalid format.
    ///   - reason: The reason why the format is invalid.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func invalidFormat(field: String, reason: String) -> DNSMessageError {
        Self.init(backing: .invalidFormat(field: field, reason: reason))
    }

    /// Malformed record data.
    /// - Parameters:
    ///   - recordType: The type of record that is malformed.
    ///   - reason: The reason why the record is malformed.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func malformedRecord(recordType: String, reason: String) -> DNSMessageError {
        Self.init(backing: .malformedRecord(recordType: recordType, reason: reason))
    }
}

extension DNSMessageError {
    enum Backing: Equatable, Hashable, Sendable {
        case labelNotAsciiEncoded(String)
        case emptyLabel
        case labelTooLong(Int)
        case invalidLabelFormat(String)
        case nameTooLong(Int)
        case unrecognizedLabelCode(UInt8)
        case insufficientData(expected: Int, available: Int)
        case invalidFormat(field: String, reason: String)
        case malformedRecord(recordType: String, reason: String)
    }
}
