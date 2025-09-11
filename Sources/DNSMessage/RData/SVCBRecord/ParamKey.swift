///  [RFC 9460 SVCB and HTTPS Resource Records, Nov 2023](https://datatracker.ietf.org/doc/html/rfc9460#section-14.3.2)
///
/// ```text
/// 14.3.2.  Initial Contents
///
///    The "Service Parameter Keys (SvcParamKeys)" registry has been
///    populated with the following initial registrations:
///
///    +===========+=================+================+=========+==========+
///    |   Number  | Name            | Meaning        |Reference|Change    |
///    |           |                 |                |         |Controller|
///    +===========+=================+================+=========+==========+
///    |     0     | mandatory       | Mandatory      |RFC 9460,|IETF      |
///    |           |                 | keys in this   |Section 8|          |
///    |           |                 | RR             |         |          |
///    +-----------+-----------------+----------------+---------+----------+
///    |     1     | alpn            | Additional     |RFC 9460,|IETF      |
///    |           |                 | supported      |Section  |          |
///    |           |                 | protocols      |7.1      |          |
///    +-----------+-----------------+----------------+---------+----------+
///    |     2     | no-default-alpn | No support     |RFC 9460,|IETF      |
///    |           |                 | for default    |Section  |          |
///    |           |                 | protocol       |7.1      |          |
///    +-----------+-----------------+----------------+---------+----------+
///    |     3     | port            | Port for       |RFC 9460,|IETF      |
///    |           |                 | alternative    |Section  |          |
///    |           |                 | endpoint       |7.2      |          |
///    +-----------+-----------------+----------------+---------+----------+
///    |     4     | ipv4hint        | IPv4 address   |RFC 9460,|IETF      |
///    |           |                 | hints          |Section  |          |
///    |           |                 |                |7.3      |          |
///    +-----------+-----------------+----------------+---------+----------+
///    |     5     | ech             | RESERVED       |N/A      |IETF      |
///    |           |                 | (held for      |         |          |
///    |           |                 | Encrypted      |         |          |
///    |           |                 | ClientHello)   |         |          |
///    +-----------+-----------------+----------------+---------+----------+
///    |     6     | ipv6hint        | IPv6 address   |RFC 9460,|IETF      |
///    |           |                 | hints          |Section  |          |
///    |           |                 |                |7.3      |          |
///    +-----------+-----------------+----------------+---------+----------+
///    |65280-65534| N/A             | Reserved for   |RFC 9460 |IETF      |
///    |           |                 | Private Use    |         |          |
///    +-----------+-----------------+----------------+---------+----------+
///    |   65535   | N/A             | Reserved       |RFC 9460 |IETF      |
///    |           |                 | ("Invalid      |         |          |
///    |           |                 | key")          |         |          |
///    +-----------+-----------------+----------------+---------+----------+
///
/// parsing done via:
///   *  a 2 octet field containing the SvcParamKey as an integer in
///      network byte order.  (See Section 14.3.2 for the defined values.)
/// ```
public struct SVCParamKey: Equatable, Hashable, Sendable {
    public let rawValue: UInt16

    private static var registeredParams: [Self: any SVCParamValue.Type] = [
        .mandatory: SVCMandatory.self,
        .alpn: SVCALPN.self,
        .noDefaultAlpn: SVCNoDefaultALPN.self,
        .port: SVCPort.self,
        .ipv4Hint: SVCIPv4Hint.self,
        .ipv6Hint: SVCIPv6Hint.self,
        .ohttp: SVCObliviousHTTP.self,
    ]

    public static func getKeyName(for key: Self) -> String {
        registeredParams[key]?.name ?? "key(\(key.rawValue))"
    }

    public static var mandatory: SVCParamKey { Self(rawValue: 0) }
    public static var alpn: SVCParamKey { Self(rawValue: 1) }
    public static var noDefaultAlpn: SVCParamKey { Self(rawValue: 2) }
    public static var port: SVCParamKey { Self(rawValue: 3) }
    public static var ipv4Hint: SVCParamKey { Self(rawValue: 4) }
    public static var ipv6Hint: SVCParamKey { Self(rawValue: 6) }
    public static var ohttp: SVCParamKey { Self(rawValue: 8) }

    public static func other(_ rawValue: UInt16) -> Self {
        Self(rawValue: rawValue)
    }

    public static func register<T: SVCParamValue>(_ type: T.Type) -> Bool {
        if registeredParams[T.correspondingKey] != nil {
            return false
        }
        registeredParams[T.correspondingKey] = type
        return true
    }

    public static func override<T: SVCParamValue>(_ type: T.Type) {
        registeredParams[T.correspondingKey] = type
    }

    public static func registeredParam(for key: Self) -> any SVCParamValue.Type {
        registeredParams[key] ?? SVCUnknown.self
    }
}
