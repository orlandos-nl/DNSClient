#if !os(Linux)
import Foundation
import NIO

/// A DNS PTR record. This is used for address to name mapping.
public struct PTRRecord: DNSResource {
    /// A  domain-name which points to some location in the domain name space.
    public let domainName: [DNSLabel]

    public static func read(from buffer: inout ByteBuffer, length: Int) -> PTRRecord? {
        guard let domainName = buffer.readLabels() else {
            return nil
        }
        return PTRRecord(domainName: domainName)
    }
    
    public init(domainName: [DNSLabel]) {
        self.domainName = domainName
    }
}

extension DNSClient {
    /// Request IPv4 inverse address (PTR records) from nameserver
    ///
    /// PTR Records are for mapping IP addresses to Internet domain names
    /// Reverse DNS is also used for functions such as:
    /// - Network troubleshooting and testing
    /// - Checking domain names for suspicious information, such as overly generic reverse DNS names, dialup users or dynamically-assigned addresses in an attempt to limit email spam
    /// - Screening spam/phishing groups who forge domain information
    /// - Data logging and analysis within web servers
    ///
    /// Background references:
    /// - Management Guidelines & Operational Requirements for the Address and Routing Parameter Area Domain ("arpa") [IETF RFC 3172](https://www.rfc-editor.org/rfc/rfc3172.html)
    /// - IANA [.ARPA Zone Management](https://www.iana.org/domains/arpa)
    /// - About reverse DNS at [ARIN](https://www.arin.net/resources/manage/reverse/)
    ///
    /// - Parameter address: IPv4 Address with four dotted decial unsigned integers between the values of 0...255
    /// - Returns: A future with the resource record containing a domain name associated with the IPv4 Address.
    public func ipv4InverseAddress(_ address: String) -> EventLoopFuture<[ResourceRecord<PTRRecord>]> {
        // A.B.C.D -> D.C.B.A.IN-ADDR.ARPA.
        let inAddrArpaDomain = address
            .split(separator: ".")
            .map(String.init)
            .reversed()
            .joined(separator: ".")
            .appending(".in-addr.arpa.")
        
        return self.sendQuery(forHost: inAddrArpaDomain, type: .ptr).map { message in
            return message.answers.compactMap { answer in
                guard case .ptr(let record) = answer else { return nil }
                return record
            }
        }
    }
    
    /// Request IPv6 inverse address (PTR records) from nameserver
    ///
    ///  Inverse addressing queries use DNS PTR Records.
    ///  An IPv6 address "2001:503:c27::2:30" is transformed into an inverse domain, then DNS query performed to get associated domain name.
    ///  0.3.0.0.2.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.7.2.c.0.3.0.5.0.1.0.0.2.ip6.arpa    domainname = j.root-servers.net.
    ///
    /// - Parameter address: IPv6 Address in long or compressed zero format
    /// - Returns: A future with the resource record containing a domain name associated with the IPv6 Address.
    /// - Throws: IOError(errnoCode: EINVAL, reason: #function) , IOError(errnoCode: errno, reason: #function)
    public func ipv6InverseAddress(_ address: String) throws -> EventLoopFuture<[ResourceRecord<PTRRecord>]> {
        var ipv6Addr = in6_addr()
        
        let retval = withUnsafeMutablePointer(to: &ipv6Addr) {
            inet_pton(AF_INET6, address, UnsafeMutablePointer($0))
        }
        
        if retval == 0 {
            throw IOError(errnoCode: EINVAL, reason: #function)
        } else if retval == -1 {
            throw IOError(errnoCode: errno, reason: #function)
        }
        
        let inAddrArpaDomain = String(format: "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                      ipv6Addr.__u6_addr.__u6_addr8.0,
                      ipv6Addr.__u6_addr.__u6_addr8.1,
                      ipv6Addr.__u6_addr.__u6_addr8.2,
                      ipv6Addr.__u6_addr.__u6_addr8.3,
                      ipv6Addr.__u6_addr.__u6_addr8.4,
                      ipv6Addr.__u6_addr.__u6_addr8.5,
                      ipv6Addr.__u6_addr.__u6_addr8.6,
                      ipv6Addr.__u6_addr.__u6_addr8.7,
                      ipv6Addr.__u6_addr.__u6_addr8.8,
                      ipv6Addr.__u6_addr.__u6_addr8.9,
                      ipv6Addr.__u6_addr.__u6_addr8.10,
                      ipv6Addr.__u6_addr.__u6_addr8.11,
                      ipv6Addr.__u6_addr.__u6_addr8.12,
                      ipv6Addr.__u6_addr.__u6_addr8.13,
                      ipv6Addr.__u6_addr.__u6_addr8.14,
                      ipv6Addr.__u6_addr.__u6_addr8.15
        ).reversed()
         .map { "\($0)" }
         .joined(separator: ".")
         .appending(".ip6.arpa.")
        
        return self.sendQuery(forHost: inAddrArpaDomain, type: .ptr).map { message in
            return message.answers.compactMap { answer in
                guard case .ptr(let record) = answer else { return nil }
                return record
            }
        }
    }
}

extension PTRRecord: CustomStringConvertible {
    public var description: String {
        "\(Self.self): " + domainName.string
    }
}
#endif