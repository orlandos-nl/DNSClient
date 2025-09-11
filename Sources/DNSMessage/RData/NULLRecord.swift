import Foundation
import NIOCore

/// [RFC 1035, DOMAIN NAMES - IMPLEMENTATION AND SPECIFICATION, November 1987](https://tools.ietf.org/html/rfc1035)
///
/// 3.3.10. NULL RDATA format (EXPERIMENTAL)
///
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                  <anything>                   /
///     /                                               /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///
/// Anything at all may be in the RDATA field so long as it is 65535 octets
/// or less.
///
/// Mockapetris                                                    [Page 17]
/// RFC 1035        Domain Implementation and Specification    November 1987
///
/// NULL records cause no additional section processing.  NULL RRs are not
/// allowed in master files.  NULLs are used as placeholders in some
/// experimental extensions of the DNS.
public struct NULLRecord: DNSResourceData {
    public let data: [UInt8]

    public var description: String {
        "\(data.map({ String(format: "%02X", $0) }).joined(separator: " "))"
    }

    public static var name: String { "NULL" }
    public static var encoding: DNSRDataEncoding { .standardRecord }
    public static var resourceType: DNSResourceType { .null }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard let data = decoder.buffer.readBytes(length: length) else {
            throw DNSMessageError.insufficientData(expected: length, available: decoder.buffer.readableBytes)
        }

        self.data = data
    }

    public init(data: [UInt8]) throws {
        guard data.count <= UInt16.max else {
            throw DNSMessageError.rDataTooLarge(totalSize: data.count, maxSize: Int(UInt16.max))
        }

        self.data = data
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        encoder.buffer.writeBytes(data)
    }
}
