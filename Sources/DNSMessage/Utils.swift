import Foundation
import NIO

/// Extension to SocketAddress to support creation from byte arrays
extension SocketAddress {
    /// Creates a SocketAddress from IP address bytes, trying IPv4 first then IPv6
    /// - Parameters:
    ///   - ipBytes: Array of bytes (4 for IPv4, 16 for IPv6)
    ///   - port: Port number
    /// - Throws: Error if the bytes don't represent a valid IP address
    internal init(ipBytes: [UInt8], port: Int) throws {
        // Try IPv4 first (4 bytes)
        if ipBytes.count == 4 {
            var addr = in_addr()
            withUnsafeMutableBytes(of: &addr.s_addr) { ptr in
                ptr.copyBytes(from: ipBytes)
            }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let result = inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))!
            let ipString = String(cString: result)
            try self.init(ipAddress: ipString, port: port)
            return
        }

        // Try IPv6 (16 bytes)
        if ipBytes.count == 16 {
            var addr = in6_addr()
            withUnsafeMutableBytes(of: &addr.__u6_addr.__u6_addr8) { ptr in
                ptr.copyBytes(from: ipBytes)
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let result = inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))!
            let ipString = String(cString: result)
            try self.init(ipAddress: ipString, port: port)
            return
        }

        // Invalid byte length - create descriptive error message
        let byteCount = ipBytes.count
        throw SocketAddressError.failedToParseIPString(
            "Invalid IP address bytes (length: \(byteCount))"
        )
    }
}

extension String {
    internal var isValidCharacterString: Bool {
        self.utf8.count <= UInt8.max
    }
}
