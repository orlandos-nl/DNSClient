import Foundation

/// A DNS character-string as defined in RFC 1035.
///
/// A character-string is a single length octet followed by that number of characters.
/// Character-strings can be up to 255 characters in length (not including the length octet).
///
/// This type provides a safe wrapper around character-string data with automatic validation
/// and convenient string conversion methods.
public struct DNSCharacterString: Equatable, Hashable, Sendable {
    /// The raw bytes of the character-string (without length prefix)
    public let bytes: [UInt8]

    /// Initialize a CharacterString from raw bytes
    /// - Parameter bytes: The character data (must be 1-255 bytes)
    /// - Throws: DNSMessageError.characterStringTooLong if bytes is empty or > 255 bytes
    public init(bytes: [UInt8]) throws {
        guard !bytes.isEmpty && bytes.count <= 255 else {
            throw DNSMessageError.characterStringTooLong(bytes.count)
        }
        self.bytes = bytes
    }

    /// Initialize a CharacterString from a Swift String
    /// - Parameter string: The string to convert (UTF-8 encoded bytes must be 1-255 bytes)
    /// - Throws: DNSMessageError.characterStringTooLong if string is empty or > 255 UTF-8 bytes
    public init(string: String) throws {
        let bytes = Array(string.utf8)
        try self.init(bytes: bytes)
    }

    /// Convert the character-string to a Swift String
    /// - Returns: UTF-8 decoded string, or "<invalid>" if bytes are not valid UTF-8
    public var string: String {
        String(bytes: self.bytes, encoding: .utf8) ?? "<invalid>"
    }

    /// The length of the character-string in bytes
    public var count: Int {
        self.bytes.count
    }
}

extension DNSCharacterString: CustomStringConvertible {
    public var description: String {
        self.string
    }
}
