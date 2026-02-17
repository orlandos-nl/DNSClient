import DNSProtocol

// Re-export DNSProtocolError for backward compatibility
public typealias ProtocolError = DNSProtocolError
package typealias SRVServiceUnavailable = DNSProtocol.SRVServiceUnavailable

struct UnableToParseConfig: Error {}
struct MissingNameservers: Error {}
struct CancelError: Error {}
struct AuthorityNotFound: Error {}
struct UnknownQuery: Error {}
