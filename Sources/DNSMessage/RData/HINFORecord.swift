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
    public var cpu: DNSCharacterString
    public var os: DNSCharacterString

    public var description: String {
        "\(cpu) \(os)"
    }

    public static var encoding: DNSRDataEncoding { .standardRecord }
    public static var resourceType: DNSResourceType { .hinfo }

    public static var name: String {
        "HINFO"
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        self.cpu = try decoder.readCharacterString()
        self.os = try decoder.readCharacterString()
    }

    public init(cpu: DNSCharacterString, os: DNSCharacterString) {
        self.cpu = cpu
        self.os = os
    }

    public init(cpu: String, os: String) throws {
        self.cpu = try .init(string: cpu)
        self.os = try .init(string: os)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        var written = 0

        written += try encoder.writeCharacterString(self.cpu)
        written += try encoder.writeCharacterString(self.os)

        return written
    }

}
