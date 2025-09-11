import ExtrasBase64
import Foundation

/// HTTPS records are identical to SVCB records except for the DNS record type.
/// [RFC 9460 SVCB and HTTPS Resource Records, Section 9](https://datatracker.ietf.org/doc/html/rfc9460#section-9)
///
/// ```text
/// 9.  HTTPS RR: SVCB-compatible RR for HTTPS origins
///
///   The HTTPS RR type is defined as a SVCB-compatible RR type, meaning that
///   it has the same wire format as the SVCB RR.  SVCB-compatible RR types
///   are defined in the SVCB specification [SVCB].
///
///   The HTTPS RR uses the same registry as SVCB for SvcParamKeys.  This
///   means that the meaning of SvcParamKeys is identical between HTTPS and
///   SVCB RRs.  New SvcParamKeys registered for use in HTTPS RRs also apply
///   to SVCB RRs unless specified otherwise.
///
///   The HTTPS RR type also shares SVCB's requirement that in ServiceMode,
///   at least one of the "port", "alpn", and "ipv4hint"/"ipv6hint"
///   SvcParamKeys MUST be included, and the TargetName MUST NOT be ".".
/// ```
public struct HTTPSRecord: DNSResourceData {
    /// The underlying SVCB record that provides the actual functionality
    private var svcbRecord: SVCBRecord

    /// Access to the wrapped SVCB record's svcPriority
    public var svcPriority: UInt16 {
        get { self.svcbRecord.svcPriority }
        set { self.svcbRecord.svcPriority = newValue }
    }

    /// Access to the wrapped SVCB record's targetName
    public var targetName: DNSName {
        get { self.svcbRecord.targetName }
        set { self.svcbRecord.targetName = newValue }
    }

    /// Access to the wrapped SVCB record's svcParams
    public var svcParams: [SVCParam] {
        get { self.svcbRecord.svcParams }
        set { self.svcbRecord.svcParams = newValue }
        _modify {
            yield &svcbRecord.svcParams
        }
    }

    public var description: String {
        "\(self.svcbRecord)"
    }

    public static var encoding: DNSRDataEncoding { .other }
    public static var resourceType: DNSResourceType { .https }
    public static var name: String { "HTTPS" }

    /// Initialize with specific values
    public init(
        svcPriority: UInt16,
        targetName: DNSName,
        svcParams: [SVCParam] = []
    ) {
        self.svcbRecord = SVCBRecord(
            svcPriority: svcPriority,
            targetName: targetName,
            svcParams: svcParams
        )
    }

    /// Initialize from an existing SVCB record
    public init(svcb: SVCBRecord) {
        self.svcbRecord = svcb
    }

    /// Decode from a decoder using Result pattern
    public init(from decoder: inout DNSDecoder, length: Int) throws {
        self.init(svcb: try .init(from: &decoder, length: length))
    }

    /// Write by delegating to the wrapped SVCB record
    public func write(encoder: inout DNSEncoder) throws -> Int {
        try svcbRecord.write(encoder: &encoder)
    }
}
