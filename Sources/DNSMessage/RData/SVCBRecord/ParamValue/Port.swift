import Foundation
import NIOCore

/// [RFC 9460 SVCB and HTTPS Resource Records](https://www.rfc-editor.org/rfc/rfc9460.html#name-port)
///
/// ```text
/// 7.2.  "port"
///
///    The "port" SvcParamKey defines the TCP or UDP port that should be
///    used to reach this alternative endpoint.  If this key is not present,
///    clients SHALL use the authority endpoint's port number.
///
///    The presentation value of the SvcParamValue is a single decimal
///    integer between 0 and 65535 in ASCII.  Any other value (e.g., an
///    empty value) is a syntax error.  To enable simpler parsing, this
///    SvcParamValue MUST NOT contain escape sequences.
///
///    The wire format of the SvcParamValue is the corresponding 2-octet
///    numeric value in network byte order.
///
///    If a port-restricting firewall is in place between some client and
///    the service endpoint, changing the port number might cause that
///    client to lose access to the service, so operators should exercise
///    caution when using this SvcParamKey to specify a non-default port.
/// ```
public struct SVCPort: SVCParamValue {
    public let port: UInt16

    public var description: String { "\(self.port)" }

    public static var correspondingKey: SVCParamKey = .port
    public static let name: String = "port"

    public init(port: UInt16) {
        self.port = port
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length == 2 else {
            throw DNSMessageError.invalidFormat(field: "SVC Port", reason: "length must be 2 bytes, got \(length)")
        }

        guard let port: UInt16 = decoder.buffer.readInteger() else {
            throw DNSMessageError.insufficientData(expected: 2, available: decoder.buffer.readableBytes)
        }

        self.port = port
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        encoder.buffer.writeInteger(self.port)
    }

    public static func == (lhs: SVCPort, rhs: SVCPort) -> Bool {
        lhs.port == rhs.port
    }
}
