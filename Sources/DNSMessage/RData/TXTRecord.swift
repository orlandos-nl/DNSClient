import Foundation
import NIOCore

/// 3.3.14. TXT RDATA format
///
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                   TXT-DATA                    /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///
/// where:
///
/// TXT-DATA        One or more <character-string>s.
///
/// TXT RRs are used to hold descriptive text.  The semantics of the text
/// depends on the domain where it is found.
public struct TXTRecord: DNSResourceData {
    public var txtData: [[UInt8]]

    public var description: String {
        let txtString: String = txtData.map({
            String.init(bytes: $0, encoding: .utf8) ?? "<txt record not utf8>"
        }).joined(separator: " ")

        return "\(txtString)"
    }

    public static let name: String = "TXT"
    public static let encoding: DNSRDataEncoding = .standardRecord
    public static let resourceType: DNSResourceType = .txt

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        var txtData: [[UInt8]] = []
        var remainingLength = length

        while remainingLength > 0 {
            let txt = try decoder.readCharacterString()
            txtData.append(txt)
            remainingLength -= Int(txt.count) + 1
        }

        self.txtData = txtData
    }

    public init(txtStrings: [String]) throws {
        var txtData: [[UInt8]] = []
        var totalBytes = 0

        for string in txtStrings {
            let bytes = string.utf8
            guard string.isValidCharacterString else {
                throw DNSMessageError.characterStringTooLong(bytes.count)
            }
            totalBytes += bytes.count + 1  // +1 for length prefix per string
            txtData.append(.init(bytes))
        }

        guard totalBytes <= Int(UInt16.max) else {
            throw DNSMessageError.rDataTooLarge(totalSize: totalBytes, maxSize: Int(UInt16.max))
        }

        self.txtData = txtData
    }

    public init(txtData: [[UInt8]]) throws {
        var totalBytes = 0

        for data in txtData {
            guard data.count <= 255 else {
                throw DNSMessageError.characterStringTooLong(data.count)
            }
            totalBytes += data.count + 1  // +1 for length prefix per string
        }

        guard totalBytes <= Int(UInt16.max) else {
            throw DNSMessageError.rDataTooLarge(totalSize: totalBytes, maxSize: Int(UInt16.max))
        }

        self.txtData = txtData
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        var written = 0

        for txt in txtData {
            written += try encoder.writeCharacterString(txt)
        }

        return written
    }
}
