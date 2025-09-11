import Foundation
import NIOCore

/// [RFC 9460 SVCB and HTTPS Resource Records, Nov 2023](https://datatracker.ietf.org/doc/html/rfc9460#section-7.1)
///
/// ```text
/// 7.1.  "alpn" and "no-default-alpn"
///
///   The "alpn" and "no-default-alpn" SvcParamKeys together indicate the
///   set of Application-Layer Protocol Negotiation (ALPN) protocol
///   identifiers [ALPN] and associated transport protocols supported by
///   this service endpoint (the "SVCB ALPN set").
///
///   As with Alt-Svc [AltSvc], each ALPN protocol identifier is used to
///   identify the application protocol and associated suite of protocols
///   supported by the endpoint (the "protocol suite").  The presence of an
///   ALPN protocol identifier in the SVCB ALPN set indicates that this
///   service endpoint, described by TargetName and the other parameters
///   (e.g., "port"), offers service with the protocol suite associated
///   with this ALPN identifier.
///
///   Clients filter the set of ALPN identifiers to match the protocol
///   suites they support, and this informs the underlying transport
///   protocol used (such as QUIC over UDP or TLS over TCP).  ALPN protocol
///   identifiers that do not uniquely identify a protocol suite (e.g., an
///   Identification Sequence that can be used with both TLS and DTLS) are
///   not compatible with this SvcParamKey and MUST NOT be included in the
///   SVCB ALPN set.
///
/// 7.1.1.  Representation
///
///   ALPNs are identified by their registered "Identification Sequence"
///   (alpn-id), which is a sequence of 1-255 octets.
///
///   alpn-id = 1*255OCTET
///
///   For "alpn", the presentation value SHALL be a comma-separated list
///   (Appendix A.1) of one or more alpn-ids.  Zone-file implementations
///   MAY disallow the "," and "\" characters in ALPN IDs instead of
///   implementing the value-list escaping procedure, relying on the opaque
///   key format (e.g., key1=\002h2) in the event that these characters are
///   needed.
///
///   The wire-format value for "alpn" consists of at least one alpn-id
///   prefixed by its length as a single octet, and these length-value
///   pairs are concatenated to form the SvcParamValue.  These pairs MUST
///   exactly fill the SvcParamValue; otherwise, the SvcParamValue is
///   malformed.
///
///   For "no-default-alpn", the presentation and wire-format values MUST
///   be empty.  When "no-default-alpn" is specified in an RR, "alpn" must
///   also be specified in order for the RR to be "self-consistent"
///   (Section 2.4.3).
///
///   Each scheme that uses this SvcParamKey defines a "default set" of
///   ALPN IDs that are supported by nearly all clients and servers; this
///   set MAY be empty.  To determine the SVCB ALPN set, the client starts
///   with the list of alpn-ids from the "alpn" SvcParamKey, and it adds
///   the default set unless the "no-default-alpn" SvcParamKey is present.
///
/// 7.1.2.  Use
///
///   To establish a connection to the endpoint, clients MUST
///
///   1.  Let SVCB-ALPN-Intersection be the set of protocols in the SVCB
///       ALPN set that the client supports.
///
///   2.  Let Intersection-Transports be the set of transports (e.g., TLS,
///       DTLS, QUIC) implied by the protocols in SVCB-ALPN-Intersection.
///
///   3.  For each transport in Intersection-Transports, construct a
///       ProtocolNameList containing the Identification Sequences of all
///       the client's supported ALPN protocols for that transport, without
///       regard to the SVCB ALPN set.
///
///   For example, if the SVCB ALPN set is ["http/1.1", "h3"] and the
///   client supports HTTP/1.1, HTTP/2, and HTTP/3, the client could
///   attempt to connect using TLS over TCP with a ProtocolNameList of
///   ["http/1.1", "h2"] and could also attempt a connection using QUIC
///   with a ProtocolNameList of ["h3"].
///
///   Once the client has constructed a ClientHello, protocol negotiation
///   in that handshake proceeds as specified in [ALPN], without regard to
///   the SVCB ALPN set.
///
///   Clients MAY implement a fallback procedure, using a less-preferred
///   transport if more-preferred transports fail to connect.  This
///   fallback behavior is vulnerable to manipulation by a network attacker
///   who blocks the more-preferred transports, but it may be necessary for
///   compatibility with existing networks.
///
///   With this procedure in place, an attacker who can modify DNS and
///   network traffic can prevent a successful transport connection but
///   cannot otherwise interfere with ALPN protocol selection.  This
///   procedure also ensures that each ProtocolNameList includes at least
///   one protocol from the SVCB ALPN set.
///
///   Clients SHOULD NOT attempt connection to a service endpoint whose
///   SVCB ALPN set does not contain any supported protocols.
///
///   To ensure consistency of behavior, clients MAY reject the entire SVCB
///   RRset and fall back to basic connection establishment if all of the
///   compatible RRs indicate "no-default-alpn", even if connection could
///   have succeeded using a non-default ALPN protocol.
///
///   Zone operators SHOULD ensure that at least one RR in each RRset
///   supports the default transports.  This enables compatibility with the
///   greatest number of clients.
/// ```
public struct SVCALPN: SVCParamValue {
    public internal(set) var alpns: [[UInt8]]

    public var description: String {
        self.alpns.lazy.map({
            String(bytes: $0, encoding: .utf8) ?? "<invalid ALPN>"
        }).joined(separator: ",")
    }

    public static let correspondingKey: SVCParamKey = .alpn
    public static let name: String = "alpn"

    public init(alpns: [[UInt8]]) throws {
        guard !alpns.isEmpty else {
            throw DNSMessageError.emptyRequiredCollection("SVC ALPN alpns")
        }

        for alpn in alpns {
            guard !alpn.isEmpty && alpn.count <= 255 else {
                throw DNSMessageError.invalidFormat(field: "SVC ALPN alpn", reason: "each ALPN must be 1-255 octets")
            }
        }

        self.alpns = alpns
    }

    public init(alpnStrings: [String]) throws {
        guard !alpnStrings.isEmpty else {
            throw DNSMessageError.emptyRequiredCollection("SVC ALPN alpns")
        }

        var alpns: [[UInt8]] = []

        for alpnString in alpnStrings {
            let bytes = Array(alpnString.utf8)
            guard !bytes.isEmpty && bytes.count <= 255 else {
                throw DNSMessageError.invalidFormat(field: "SVC ALPN alpn", reason: "each ALPN must be 1-255 octets")
            }
            alpns.append(bytes)
        }

        self.alpns = alpns
    }

    public init(commaSeparatedALPNs: String) throws {
        let alpnStrings = commaSeparatedALPNs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        try self.init(alpnStrings: alpnStrings)
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length >= 2 else {
            throw DNSMessageError.invalidFormat(field: "SVC ALPN", reason: "length must be at least 2 bytes")
        }

        var remainingLength = length
        var alpns: [[UInt8]] = []

        while remainingLength > 0 {
            let alpn = try decoder.readCharacterString()
            guard !alpn.isEmpty else {
                throw DNSMessageError.invalidFormat(field: "SVC ALPN", reason: "each ALPN must be 1-255 octets")
            }
            alpns.append(alpn)
            remainingLength -= Int(alpn.count) + 1
        }

        self.alpns = alpns
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        var written = 0

        for alpn in self.alpns {
            written += try encoder.writeCharacterString(alpn)
        }

        return written
    }
}

/// See `SVCALPN`
public struct SVCNoDefaultALPN: SVCParamValue {
    public var description: String { "" }  // Has no data

    public static let correspondingKey: SVCParamKey = .noDefaultAlpn
    public static let name: String = "no-default-alpn"

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length == 0 else {
            throw DNSMessageError.invalidFormat(field: "SVC NoDefaultALPN", reason: "length must be 0")
        }

        return
    }

    public init() {
        // No properties to initialize
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        0
    }
}
