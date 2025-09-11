import ExtrasBase64
import Foundation
import NIOCore

/// A fallback SVCParamValue implementation for handling unknown or unrecognized SVC parameter types.
///
/// When parsing SVCB records, if a SvcParamKey is encountered that doesn't have a registered
/// concrete SVCParamValue type, this struct is used to store the raw bytes of the parameter value.
/// This allows the parser to gracefully handle future or proprietary SVC parameter extensions
/// without failing completely.
///
/// The raw bytes are preserved exactly as they appear in the wire format, enabling the data
/// to be re-encoded identically even if the specific parameter semantics are unknown to this
/// implementation.
public struct SVCUnknown: SVCParamValue {
    public var bytes: [UInt8]

    public var description: String {
        "Unknown(\(Base64.encodeToString(bytes: self.bytes)))"
    }

    /// Uses UInt16.max as a placeholder key value since this represents any unknown parameter
    public static var correspondingKey: SVCParamKey { .other(UInt16.max) }
    public static var name: String { "unknown" }

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard let bytes = decoder.buffer.readBytes(length: length) else {
            throw DNSMessageError.insufficientData(expected: length, available: decoder.buffer.readableBytes)
        }

        self.bytes = bytes
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        encoder.buffer.writeBytes(self.bytes)
    }
}
