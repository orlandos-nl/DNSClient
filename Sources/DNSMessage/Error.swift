import Foundation

/// Errors that can occur during DNS message parsing, validation, or construction.
public struct DNSMessageError: Error, Equatable, Hashable, Sendable {
    private var backing: Backing

    fileprivate init(backing: Backing) {
        self.backing = backing
    }

    /// The provided string is not ASCII encoded.
    /// - Parameter string: The string that is not ASCII encoded.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func stringNotAsciiEncoded(_ string: String) -> DNSMessageError {
        Self.init(backing: .stringNotAsciiEncoded(string))
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

    /// Invalid resource type for DNS question.
    /// - Parameter type: The resource type that is invalid for questions.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func invalidQuestionType(_ type: DNSResourceType) -> DNSMessageError {
        Self.init(backing: .invalidQuestionType(type))
    }

    /// Invalid resource type for DNS resource record.
    /// - Parameter type: The resource type that is invalid for resource records.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func invalidResourceRecordType(_ type: DNSResourceType) -> DNSMessageError {
        Self.init(backing: .invalidResourceRecordType(type))
    }

    /// A character-string cannot exceed 255 bytes in length.
    /// - Parameter length: The length of the character-string that is too long.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func characterStringTooLong(_ length: Int) -> DNSMessageError {
        Self.init(backing: .characterStringTooLong(length))
    }

    /// The total size of RDATA cannot exceed the maximum allowed.
    /// - Parameters:
    ///   - totalSize: The total size that exceeds the limit.
    ///   - maxSize: The maximum allowed size.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func rDataTooLarge(totalSize: Int, maxSize: Int) -> DNSMessageError {
        Self.init(backing: .rDataTooLarge(totalSize: totalSize, maxSize: maxSize))
    }

    /// A required collection cannot be empty.
    /// - Parameter collectionName: The name of the collection that cannot be empty.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func emptyRequiredCollection(_ collectionName: String) -> DNSMessageError {
        Self.init(backing: .emptyRequiredCollection(collectionName))
    }
}

extension DNSMessageError: CustomStringConvertible {
    public var description: String {
        self.backing.description
    }
}

extension DNSMessageError {
    enum Backing: Equatable, Hashable, Sendable, CustomStringConvertible {
        case stringNotAsciiEncoded(String)
        case emptyLabel
        case labelTooLong(Int)
        case invalidLabelFormat(String)
        case nameTooLong(Int)
        case unrecognizedLabelCode(UInt8)
        case insufficientData(expected: Int, available: Int)
        case invalidFormat(field: String, reason: String)
        case malformedRecord(recordType: String, reason: String)
        case invalidQuestionType(DNSResourceType)
        case invalidResourceRecordType(DNSResourceType)
        case characterStringTooLong(Int)
        case rDataTooLarge(totalSize: Int, maxSize: Int)
        case emptyRequiredCollection(String)

        var description: String {
            switch self {
            case .stringNotAsciiEncoded(let string):
                return "String is not ASCII encoded: \(string)"
            case .emptyLabel:
                return "DNS label cannot be empty"
            case .labelTooLong(let length):
                return "DNS label too long: \(length) bytes (max 63)"
            case .invalidLabelFormat(let label):
                return "Invalid DNS label format: \(label)"
            case .nameTooLong(let length):
                return "DNS name too long: \(length) bytes (max 255)"
            case .unrecognizedLabelCode(let code):
                return "Unrecognized DNS label code: 0x\(String(code, radix: 16))"
            case .insufficientData(let expected, let available):
                return "Insufficient data: expected \(expected) bytes, got \(available)"
            case .invalidFormat(let field, let reason):
                return "Invalid format in \(field): \(reason)"
            case .malformedRecord(let recordType, let reason):
                return "Malformed \(recordType) record: \(reason)"
            case .invalidQuestionType(let type):
                return "Invalid question type: \(type)"
            case .invalidResourceRecordType(let type):
                return "Invalid resource record type: \(type)"
            case .characterStringTooLong(let length):
                return "Character string too long: \(length) bytes (max 255)"
            case .rDataTooLarge(let totalSize, let maxSize):
                return "RData too large: \(totalSize) bytes (max \(maxSize))"
            case .emptyRequiredCollection(let field):
                return "Required collection \(field) cannot be empty"
            }
        }
    }
}
