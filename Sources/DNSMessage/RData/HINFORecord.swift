import Foundation
import NIOCore

/// 3.3.2. HINFO RDATA format
///
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                      CPU                      /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///     /                       OS                      /
///     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
///
/// where:
///
/// CPU             A <character-string> which specifies the CPU type.
///
/// OS              A <character-string> which specifies the operating
///                 system type.
///
/// Standard values for CPU and OS can be found in [RFC-1010].
///
/// HINFO records are used to acquire general information about a host.  The
/// main use is for protocols such as FTP that can use special procedures
/// when talking between machines or operating systems of the same type.
public struct HINFORecord: DNSResourceData {
    public let cpu: [UInt8]
    public let os: [UInt8]

    public var description: String {
        let cpu = String(bytes: self.cpu, encoding: .utf8) ?? "<cpu unknown>"
        let os = String(bytes: self.os, encoding: .utf8) ?? "<os unknown>"
        return "\(cpu) \(os)"
    }

    public static var encoding: DNSRDataEncoding = .standardRecord
    public static var resourceType: DNSResourceType = .hinfo

    public static var name: String {
        "HINFO"
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        self.cpu = try decoder.readCharacterString()
        self.os = try decoder.readCharacterString()
    }

    public init(cpu: [UInt8], os: [UInt8]) {
        self.cpu = cpu
        self.os = os
    }

    public init(cpu: String, os: String) throws {
        guard cpu.isValidCharacterString else {
            throw DNSMessageError.characterStringTooLong(cpu.utf8.count)
        }
        guard os.isValidCharacterString else {
            throw DNSMessageError.characterStringTooLong(os.utf8.count)
        }

        self.cpu = .init(cpu.utf8)
        self.os = .init(os.utf8)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        var written = 0

        written += try encoder.writeCharacterString(self.cpu)
        written += try encoder.writeCharacterString(self.os)

        return written
    }

}
