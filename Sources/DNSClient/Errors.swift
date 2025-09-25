/// Errors that can occur during DNS client operations, connection management, or HTTP requests.
public struct DNSClientError: Error, Equatable, Hashable, Sendable {
    internal var backing: Backing

    fileprivate init(backing: Backing) {
        self.backing = backing
    }

    /// Unable to parse DNS configuration.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func unableToParseConfig() -> DNSClientError {
        Self.init(backing: .unableToParseConfig)
    }

    /// No nameservers found in configuration.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func missingNameservers() -> DNSClientError {
        Self.init(backing: .missingNameservers)
    }

    /// Operation was cancelled.
    /// - Returns: An Error representing this failure.
    @inline(never)
    public static func cancelError() -> DNSClientError {
        Self.init(backing: .cancelError)
    }
}

extension DNSClientError: CustomStringConvertible {
    public var description: String {
        self.backing.description
    }

    enum Backing: Equatable, Hashable, Sendable, CustomStringConvertible {
        case unableToParseConfig
        case missingNameservers
        case cancelError

        var description: String {
            switch self {
            case .unableToParseConfig:
                return "Unable to parse DNS configuration"
            case .missingNameservers:
                return "No nameservers found in configuration"
            case .cancelError:
                return "Operation was cancelled"
            }
        }
    }
}

// MARK: - Legacy Error Types (Deprecated)
// These are kept for backward compatibility but should be migrated to DNSClientError

@available(
    *,
    deprecated,
    renamed: "DNSClientError.unableToParseConfig"
)
struct UnableToParseConfig: Error {}

@available(
    *,
    deprecated,
    renamed: "DNSClientError.missingNameservers"
)
struct MissingNameservers: Error {}

@available(
    *,
    deprecated,
    renamed: "DNSClientError.cancelError"
)
struct CancelError: Error {}
struct AuthorityNotFound: Error {}
struct ProtocolError: Error {}
struct UnknownQuery: Error {}
