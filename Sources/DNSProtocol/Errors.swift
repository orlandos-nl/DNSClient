/// Error thrown when a DNS message cannot be parsed.
public struct DNSProtocolError: Error {
    public init() {}
}

/// Error used by SRV dot-target semantics to indicate service unavailability.
///
/// Per RFC 2782, a single SRV answer with target "." means the service is
/// explicitly not available at this domain.
package struct SRVServiceUnavailable: Error {
    package init() {}
}
