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
    public var txtData: [DNSCharacterString]

    public var description: String {
        txtData.map({ $0.description }).joined(separator: " ")
    }

    public static let name: String = "TXT"
    public static let encoding: DNSRDataEncoding = .standardRecord
    public static let resourceType: DNSResourceType = .txt

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        var txtData: [DNSCharacterString] = []
        var remainingLength = length

        while remainingLength > 0 {
            let txt = try decoder.readCharacterString()
            remainingLength -= txt.count + 1
            txtData.append(txt)
        }

        self.txtData = txtData
    }

    public init(txtStrings: [String]) throws {
        let txtData = try txtStrings.map { try DNSCharacterString(string: $0) }

        let totalBytes = txtData.reduce(0) { $0 + $1.count + 1 }  // +1 for length prefix per string
        guard totalBytes <= Int(UInt16.max) else {
            throw DNSMessageError.rDataTooLarge(totalSize: totalBytes, maxSize: Int(UInt16.max))
        }

        self.txtData = txtData
    }

    public init(txtData: [DNSCharacterString]) throws {
        let totalBytes = txtData.reduce(0) { $0 + $1.count + 1 }  // +1 for length prefix per string
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
