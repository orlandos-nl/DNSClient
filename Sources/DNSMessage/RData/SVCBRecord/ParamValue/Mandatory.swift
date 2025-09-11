import ExtrasBase64
import Foundation
import NIOCore

/// [RFC 9460 SVCB and HTTPS Resource Records, Nov 2023](https://datatracker.ietf.org/doc/html/rfc9460#section-8)
///
/// ```text
/// 8.  ServiceMode RR compatibility and mandatory keys
///
///    In a ServiceMode RR, a SvcParamKey is considered "mandatory" if the
///    RR will not function correctly for clients that ignore this
///    SvcParamKey.  Each SVCB protocol mapping SHOULD specify a set of keys
///    that are "automatically mandatory", i.e. mandatory if they are
///    present in an RR.  The SvcParamKey "mandatory" is used to indicate
///    any mandatory keys for this RR, in addition to any automatically
///    mandatory keys that are present.
///
///    A ServiceMode RR is considered "compatible" with a client if the
///    client recognizes all the mandatory keys, and their values indicate
///    that successful connection establishment is possible. Incompatible RRs
///    are ignored (see step 5 of the procedure defined in Section 3)
///
///    The presentation value SHALL be a comma-separated list
///    (Appendix A.1) of one or more valid SvcParamKeys, either by their
///    registered name or in the unknown-key format (Section 2.1).  Keys MAY
///    appear in any order, but MUST NOT appear more than once.  For self-
///    consistency (Section 2.4.3), listed keys MUST also appear in the
///    SvcParams.
///
///    To enable simpler parsing, this SvcParamValue MUST NOT contain escape
///    sequences.
///
///    For example, the following is a valid list of SvcParams:
///
///    ipv6hint=... key65333=ex1 key65444=ex2 mandatory=key65444,ipv6hint
///
///    In wire format, the keys are represented by their numeric values in
///    network byte order, concatenated in strictly increasing numeric order.
///
///    This SvcParamKey is always automatically mandatory, and MUST NOT
///    appear in its own value-list.  Other automatically mandatory keys
///    SHOULD NOT appear in the list either.  (Including them wastes space
///    and otherwise has no effect.)
/// ```
public struct SVCMandatory: SVCParamValue {
    public internal(set) var keys: [SVCParamKey]

    public var description: String {
        self.keys.lazy.map({ String(describing: $0) }).joined(separator: ",")
    }

    public static var correspondingKey: SVCParamKey = .mandatory
    public static let name: String = "mandatory"

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length > 0 else {
            throw DNSMessageError.invalidFormat(field: "SVC Mandatory", reason: "length must be greater than 0")
        }

        guard length % 2 == 0 else {
            throw DNSMessageError.invalidFormat(field: "SVC Mandatory", reason: "length must be even")
        }

        let keys: [SVCParamKey] = try (0..<length / 2).map({ _ in
            guard let rawValue: UInt16 = decoder.buffer.readInteger() else {
                throw DNSMessageError.insufficientData(expected: 2, available: decoder.buffer.readableBytes)
            }

            return SVCParamKey(rawValue: rawValue)
        })

        self.keys = keys
    }

    public init(keys: [SVCParamKey]) throws {
        guard !keys.isEmpty else {
            throw DNSMessageError.emptyRequiredCollection("SVCMandatory keys")
        }

        self.keys = keys
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {

        var written = 0

        // RFC 9460 Section 8: keys must be in strictly increasing numeric order in wire format
        let sortedKeys = self.keys.sorted { $0.rawValue < $1.rawValue }
        for key in sortedKeys {
            written += encoder.buffer.writeInteger(key.rawValue)
        }

        return written
    }
}
