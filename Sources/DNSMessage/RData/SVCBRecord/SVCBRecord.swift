import ExtrasBase64
import Foundation
import NIOCore

///  [RFC 9460 SVCB and HTTPS Resource Records, Nov 2023](https://datatracker.ietf.org/doc/html/rfc9460#section-2.2)
/// ```text
/// 2.2.  RDATA wire format
///
///   The RDATA for the SVCB RR consists of:
///
///   *  a 2 octet field for SvcPriority as an integer in network byte
///      order.
///   *  the uncompressed, fully-qualified TargetName, represented as a
///      sequence of length-prefixed labels as in Section 3.1 of [RFC1035].
///   *  the SvcParams, consuming the remainder of the record (so smaller
///      than 65535 octets and constrained by the RDATA and DNS message
///      sizes).
///
///   When the list of SvcParams is non-empty (ServiceMode), it contains a
///   series of SvcParamKey=SvcParamValue pairs, represented as:
///
///   *  a 2 octet field containing the SvcParamKey as an integer in
///      network byte order.  (See Section 14.3.2 for the defined values.)
///   *  a 2 octet field containing the length of the SvcParamValue as an
///      integer between 0 and 65535 in network byte order
///   *  an octet string of this length whose contents are the SvcParamValue
///      in a format determined by the SvcParamKey
///
///   SvcParamKeys SHALL appear in increasing numeric order.
///
///   Clients MUST consider an RR malformed if:
///
///   *  the end of the RDATA occurs within a SvcParam.
///   *  SvcParamKeys are not in strictly increasing numeric order.
///   *  the SvcParamValue for an SvcParamKey does not have the expected
///      format.
///
///   Note that the second condition implies that there are no duplicate
///   SvcParamKeys.
///
///   If any RRs are malformed, the client MUST reject the entire RRSet and
///   fall back to non-SVCB connection establishment.
/// ```
public struct SVCBRecord: DNSResourceData {
    ///  [RFC 9460 SVCB and HTTPS Resource Records, Nov 2023](https://datatracker.ietf.org/doc/html/rfc9460#section-2.4.1)
    /// ```text
    /// 2.4.1.  SvcPriority
    ///
    ///   When SvcPriority is 0 the SVCB record is in AliasMode
    ///   (Section 2.4.2).  Otherwise, it is in ServiceMode (Section 2.4.3).
    ///
    ///   Within a SVCB RRSet, all RRs SHOULD have the same Mode.  If an RRSet
    ///   contains a record in AliasMode, the recipient MUST ignore any
    ///   ServiceMode records in the set.
    ///
    ///   RRSets are explicitly unordered collections, so the SvcPriority field
    ///   is used to impose an ordering on SVCB RRs.  A smaller SvcPriority indicates
    ///   that the domain owner recommends the use of this record over ServiceMode
    ///   RRs with a larger SvcPriority value.
    ///
    ///   When receiving an RRSet containing multiple SVCB records with the
    ///   same SvcPriority value, clients SHOULD apply a random shuffle within
    ///   a priority level to the records before using them, to ensure uniform
    ///   load-balancing.
    /// ```
    public var svcPriority: UInt16

    ///  [RFC 9460 SVCB and HTTPS Resource Records, Nov 2023](https://datatracker.ietf.org/doc/html/rfc9460#section-2.5)
    /// ```text
    /// 2.5.  Special handling of "." in TargetName
    ///
    ///   If TargetName has the value "." (represented in the wire format as a
    ///    zero-length label), special rules apply.
    ///
    /// 2.5.1.  AliasMode
    ///
    ///    For AliasMode SVCB RRs, a TargetName of "." indicates that the
    ///    service is not available or does not exist.  This indication is
    ///    advisory: clients encountering this indication MAY ignore it and
    ///    attempt to connect without the use of SVCB.
    ///
    /// 2.5.2.  ServiceMode
    ///
    ///    For ServiceMode SVCB RRs, if TargetName has the value ".", then the
    ///    owner name of this record MUST be used as the effective TargetName.
    ///    If the record has a wildcard owner name in the zone file, the recipient
    ///    SHALL use the response's synthesized owner name as the effective TargetName.
    ///
    ///    Here, for example, "svc2.example.net" is the effective TargetName:
    ///
    ///    example.com.      7200  IN HTTPS 0 svc.example.net.
    ///    svc.example.net.  7200  IN CNAME svc2.example.net.
    ///    svc2.example.net. 7200  IN HTTPS 1 . port=8002
    ///    svc2.example.net. 300   IN A     192.0.2.2
    ///    svc2.example.net. 300   IN AAAA  2001:db8::2
    /// ```
    public var targetName: DNSName
    public var svcParams: [SVCParam]

    public var description: String {
        let params: String = self.svcParams.lazy.map { param in
            let keyDescription = SVCParamKey.getKeyName(for: param.key)
            let valueDescription = String(describing: param.value)

            if valueDescription.isEmpty {
                return keyDescription
            } else {
                return "\(keyDescription)=\(valueDescription)"
            }
        }.joined(separator: " ")

        return "\(self.svcPriority) \(self.targetName) \(params)"
    }

    public static var name: String { "SVCB" }
    public static var encoding: DNSRDataEncoding { .other }
    public static var resourceType: DNSResourceType { .svcb }

    /// Initialize with specific values
    public init(
        svcPriority: UInt16,
        targetName: DNSName,
        svcParams: [SVCParam] = []
    ) {
        self.svcPriority = svcPriority
        self.targetName = targetName
        self.svcParams = svcParams
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        let startLocation = decoder.buffer.readerIndex

        guard let svcPriority: UInt16 = decoder.buffer.readInteger() else {
            throw DNSMessageError.insufficientData(
                expected: 2,
                available: decoder.buffer.readableBytes
            )
        }

        self.svcPriority = svcPriority
        self.targetName = DNSName()
        try decoder.readDNSName(name: &self.targetName)

        let endLocation = decoder.buffer.readerIndex
        var remainingLength = length - (endLocation - startLocation)
        var svcParams: [SVCParam] = []
        var lastKeyValue = -1

        while remainingLength > 0 {
            guard
                let paramKeyRaw: UInt16 = decoder.buffer.readInteger(),
                let paramLength: UInt16 = decoder.buffer.readInteger()
            else {
                throw DNSMessageError.insufficientData(
                    expected: 4,
                    available: decoder.buffer.readableBytes
                )
            }

            guard paramKeyRaw > lastKeyValue else {
                throw DNSMessageError.invalidFormat(
                    field: "SVC param key",
                    reason: "keys must be in strictly increasing order"
                )
            }

            lastKeyValue = Int(paramKeyRaw)
            let paramKey = SVCParamKey(rawValue: paramKeyRaw)
            let paramValueType = SVCParamKey.registeredParam(for: paramKey)
            let paramValue = try paramValueType.init(from: &decoder, length: Int(paramLength))

            svcParams.append(SVCParam(key: paramKey, value: paramValue))

            remainingLength -= 4 + Int(paramLength)
        }

        self.svcParams = svcParams

        // Validate that mandatory keys actually exist in svcParams (RFC 9460 Section 8)
        try self.validateMandatoryKeys()
    }

    /// Validates that all keys listed in the mandatory parameter actually exist in svcParams
    /// RFC 9460 Section 8: "For self-consistency (Section 2.4.3), listed keys MUST also appear in the SvcParams."
    private func validateMandatoryKeys() throws {
        // Find the mandatory parameter if it exists
        guard let mandatoryParam = svcParams.first(where: { $0.key == .mandatory }) else {
            return  // No mandatory parameter, nothing to validate
        }

        guard let mandatoryValue = mandatoryParam.value as? SVCMandatory else {
            return  // Should not happen if implementation is correct
        }

        let presentKeys = Set(svcParams.map { $0.key })

        for mandatoryKey in mandatoryValue.keys {
            guard presentKeys.contains(mandatoryKey) else {
                throw DNSMessageError.invalidFormat(
                    field: "SVC mandatory keys",
                    reason: "mandatory key \(mandatoryKey.rawValue) is not present in SvcParams"
                )
            }
        }
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        try validateMandatoryKeys()
        var written = 0

        written += encoder.buffer.writeInteger(self.svcPriority)
        written += try encoder.writeDNSName(self.targetName)

        for param in self.svcParams {
            written += encoder.buffer.writeInteger(param.key.rawValue)
            written += try encoder.writeLengthPrefixed { encoder in
                if let value = param.value {
                    return try value.write(encoder: &encoder)
                } else {
                    return 0
                }
            }
        }

        return written
    }

    public static func == (lhs: SVCBRecord, rhs: SVCBRecord) -> Bool {
        lhs.svcPriority == rhs.svcPriority && lhs.targetName == rhs.targetName
            && lhs.svcParams.count == rhs.svcParams.count
            && zip(lhs.svcParams, rhs.svcParams).allSatisfy { (left, right) in
                left == right
            }
    }
}

public struct SVCParam: Sendable, CustomStringConvertible, Equatable {
    public let key: SVCParamKey
    public let value: (any SVCParamValue)?

    public var description: String {
        let keyDescription = SVCParamKey.getKeyName(for: key)
        if let value = value {
            let valueDescription = String(describing: value)
            if valueDescription.isEmpty {
                return keyDescription
            } else {
                return "\(keyDescription)=\(valueDescription)"
            }
        } else {
            return keyDescription
        }
    }

    public init(key: SVCParamKey, value: (any SVCParamValue)?) {
        self.key = key
        self.value = value
    }

    public static func == (lhs: SVCParam, rhs: SVCParam) -> Bool {
        guard lhs.key == rhs.key else { return false }

        switch (lhs.value, rhs.value) {
        case (nil, nil):
            return true
        case (let lhsValue?, let rhsValue?):
            return lhsValue.isEqual(to: rhsValue)
        default:
            return false
        }
    }
}

/// ```text
///   *  a 2 octet field containing the length of the SvcParamValue as an
///      integer between 0 and 65535 in network byte order (but constrained
///      by the RDATA and DNS message sizes).
///   *  an octet string of this length whose contents are in a format
///      determined by the SvcParamKey.
/// ``
public protocol SVCParamValue: CustomStringConvertible, Sendable, Equatable {
    static var correspondingKey: SVCParamKey { get }
    static var name: String { get }

    init(from decoder: inout DNSDecoder, length: Int) throws
    func write(encoder: inout DNSEncoder) throws -> Int

    func isEqual(to other: any SVCParamValue) -> Bool
}

extension SVCParamValue {
    public func isEqual(to other: any SVCParamValue) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}
