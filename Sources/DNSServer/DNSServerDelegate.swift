import NIO
import DNSProtocol

/// Context provided to delegate methods containing information about the incoming request.
public struct DNSRequestContext: Sendable {
    /// The remote address of the client that sent the request.
    public let remoteAddress: SocketAddress

    /// The transport protocol used (UDP or TCP).
    public let transport: DNSTransport

    public init(remoteAddress: SocketAddress, transport: DNSTransport) {
        self.remoteAddress = remoteAddress
        self.transport = transport
    }
}

/// Represents the transport protocol for a DNS request.
public enum DNSTransport: Sendable {
    case udp
    case tcp
}

/// Protocol for handling DNS queries on the server.
/// Implementations must be Sendable as they may be called from multiple event loops.
public protocol DNSServerDelegate: Sendable {
    /// Handle an incoming DNS query and return a response.
    ///
    /// - Parameters:
    ///   - query: The incoming DNS message containing one or more questions.
    ///   - context: Context information about the request (remote address, transport).
    /// - Returns: A DNS message to send as the response.
    /// - Throws: If an error occurs, the server will send a SERVFAIL response.
    func handleQuery(_ query: Message, context: DNSRequestContext) async throws -> Message
}
