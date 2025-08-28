/// 16-bit flags field in a DNS header containing various control flags.
///
/// The `Z` bit is reserved and must always be zero. The `RCODE` (Response Code)
/// is handled separately because EDNS(0) expands it from 4 to 12 bits.
public struct DNSHeaderFlags: Sendable, OptionSet {
    public var rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let response = DNSHeaderFlags(rawValue: 1 << 15)  // QR

    // Opcode is stored in bits 11-14, handled separately during encoding/decoding
    private static let opcodeMask: UInt16 = 0b0111_1000_0000_0000
    private static let opcodeShift: Int = 11

    public static let authoritativeAnswer = DNSHeaderFlags(rawValue: 1 << 10)  // AA
    public static let truncation = DNSHeaderFlags(rawValue: 1 << 9)  // TC
    public static let recursionDesired = DNSHeaderFlags(rawValue: 1 << 8)  // RD
    public static let recursionAvailable = DNSHeaderFlags(rawValue: 1 << 7)  // RA

    // Skipping Z

    public static let authenticData = DNSHeaderFlags(rawValue: 1 << 5)  // AD
    public static let checkingDisabled = DNSHeaderFlags(rawValue: 1 << 4)  // CD

    // Skipping RCODE (Return Code) as EDNS(0) has expanded it to 12 bits.
    // The lower 4 bits of RCODE will be added when serializing/deserializing.

    /// Extracts the 4-bit DNS operation code (Opcode) from the raw value and clears the opcode bits.
    ///
    /// - Returns: The corresponding `DNSOpcode` enum case.
    internal mutating func decodeOpcode() -> DNSOpcode {
        let opcodeValue = UInt8((self.rawValue & Self.opcodeMask) >> Self.opcodeShift)
        self.rawValue &= ~Self.opcodeMask  // Clear opcode bits
        return DNSOpcode(rawValue: opcodeValue)
    }

    /// Sets the 4-bit DNS operation code (Opcode) within the raw value.
    ///
    /// - Parameter opcode: The `DNSOpcode` to encode into the raw value.
    internal mutating func encodeOpcode(_ opcode: DNSOpcode) {
        let opcodeValue = UInt16(opcode.rawValue)
        self.rawValue = (self.rawValue & ~Self.opcodeMask) | (opcodeValue << Self.opcodeShift)
    }

    /// Extracts the 4-bit DNS response code from the header flags and clears the response code bits.
    /// This creates an incomplete response code that may need to be completed with EDNS bits later.
    ///
    /// - Returns: An incomplete `DNSResponseCode` with only header bits.
    internal mutating func decodeResponseCode() -> DNSResponseCode {
        let headerBits = UInt16(self.rawValue & DNSResponseCode.headerBitMask)
        self.rawValue &= ~DNSResponseCode.headerBitMask  // Clear response code bits
        return DNSResponseCode(rawValue: headerBits)
    }

    /// Sets the 4-bit DNS response code within the raw value.
    ///
    /// - Parameter responseCode: The `DNSResponseCode` to encode header bits from.
    internal mutating func encodeResponseCode(_ responseCode: DNSResponseCode) {
        let headerBits = UInt16(responseCode.headerBits())
        self.rawValue = (self.rawValue & ~DNSResponseCode.headerBitMask) | headerBits
    }
}

/// A 4-bit field that specifies the kind of query in a DNS message.
/// Valid values are 0-15 only, as opcodes are limited to 4 bits in the DNS header.
public struct DNSOpcode: Equatable, Hashable, Sendable {
    public internal(set) var rawValue: UInt8

    /// Creates a DNS opcode. Requires rawValue < 16 (4-bit limit).
    public init(rawValue: UInt8) {
        precondition(rawValue < 16)
        self.rawValue = rawValue & 0x0F
    }

    public static var query: Self { .init(rawValue: 0) }
    public static var status: Self { .init(rawValue: 2) }
    public static var notify: Self { .init(rawValue: 4) }
    public static var update: Self { .init(rawValue: 5) }
    public static var dso: Self { .init(rawValue: 6) }

    public static func other(_ rawValue: UInt8) -> Self {
        Self(rawValue: rawValue)
    }
}

/// Represents the response code (RCODE) in a DNS message, indicating the status of a query.
///
/// The original DNS header provided a 4-bit RCODE field. EDNS(0)
/// extension expanded this to 12 bits for additional status codes. A complete list of response
///     codes can be found at
///     https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml#dns-parameters-6
public struct DNSResponseCode: Equatable, Hashable, Sendable {
    public internal(set) var rawValue: UInt16

    public static var noError: Self { .init(rawValue: 0) }
    public static var formatError: Self { .init(rawValue: 1) }
    public static var serverFailure: Self { .init(rawValue: 2) }
    public static var nonExistentDomain: Self { .init(rawValue: 3) }  // NXDomain
    public static var notImplemented: Self { .init(rawValue: 4) }
    public static var refused: Self { .init(rawValue: 5) }
    public static var domainAlreadyExists: Self { .init(rawValue: 6) }  // YXDomain
    public static var rrSetAlreadyExists: Self { .init(rawValue: 7) }  // YXRRSet
    public static var nonExistentRRSet: Self { .init(rawValue: 8) }  // NXRRSet
    public static var notAuth: Self { .init(rawValue: 9) }
    public static var nameNotInZone: Self { .init(rawValue: 10) }  // NotZone
    public static var dsoTypeNotImplemented: Self { .init(rawValue: 11) }  // DSOTYPENI
    public static var badVersion: Self { .init(rawValue: 16) }  // BADVERS, BADSIG have the same value
    public static var badKey: Self { .init(rawValue: 17) }
    public static var badTime: Self { .init(rawValue: 18) }
    public static var badMode: Self { .init(rawValue: 19) }
    public static var badName: Self { .init(rawValue: 20) }
    public static var badAlgorithm: Self { .init(rawValue: 21) }
    public static var badTruncation: Self { .init(rawValue: 22) }
    public static var badCookie: Self { .init(rawValue: 23) }

    public static func other(_ rawValue: UInt16) -> Self {
        Self(rawValue: rawValue)
    }

    /// A bitmask for the lower 4 bits of the response code, which are stored in the main DNS header.
    internal static let headerBitMask: UInt16 = 0x000F
    /// A bitmask for the upper 8 bits of the response code,
    ///     which are stored in the EDNS(0) OPT record TTL field.
    internal static let ednsBitMask: UInt16 = 0x0FF0

    internal var requiresEdns: Bool {
        ednsBits() > 0
    }

    internal func headerBits() -> UInt8 {
        UInt8(truncatingIfNeeded: self.rawValue & Self.headerBitMask)
    }

    internal func ednsBits() -> UInt8 {
        UInt8(truncatingIfNeeded: (self.rawValue & Self.ednsBitMask) >> 4)
    }

    internal mutating func completeWith(ednsBits: UInt8) {
        self.rawValue = (UInt16(ednsBits) << 4) | self.rawValue
    }
}

/// MessageOptions has been deprecated in favor of the new DNS header architecture.
///
/// ## Reasons for Deprecation
/// The original `MessageOptions` combined DNS flags, operation codes, and response codes
/// into a single `OptionSet`, which had several limitations:
///
/// 1. **Protocol Validity**: Allowed invalid DNS message combinations (e.g., setting both query and status Opcodes)
/// 2. **EDNS Support**: Could not properly handle EDNS(0) extended response codes (12-bit vs 4-bit)
///
/// ## Migration Path
/// The new architecture separates these concerns into distinct types:
/// - `DNSHeaderFlags` for actual header flags (QR, AA, TC, RD, RA, AD, CD)
/// - `DNSOpcode` for operation codes (QUERY, STATUS, NOTIFY, UPDATE, DSO)
/// - `DNSResponseCode` for response codes with proper EDNS support
///
/// ### Before (deprecated):
/// ```swift
/// let options: MessageOptions = [.answer, .authoritativeAnswer, .standardQuery]
/// if options.isAnswer && options.isStandardQuery {
///     // handle response
/// }
/// ```
///
/// ### After (recommended):
/// ```swift
/// let header = DNSHeader(
///     id: 12345,
///     flags: [.response, .authoritativeAnswer],
///     opcode: .query,
///     responseCode: .NoError
/// )
/// if header.flags.contains(.response) && header.opcode == .query {
///     // handle response
/// }
/// ```
@available(
    *,
    deprecated,
    message: """
        MessageOptions has been replaced with separate DNSHeaderFlags, DNSOpcode, and DNSResponseCode types for EDNS support and protocol validity.

        Migration guide:
        - Use DNSHeaderFlags for header flags (.response, .authoritativeAnswer, etc.)
        - Use DNSOpcode for operation codes (.query, .status, etc.)
        - Use DNSResponseCode for response codes (.NoError, .FormErr, etc.)
        """
)
public typealias MessageOptions = DNSHeaderFlags
