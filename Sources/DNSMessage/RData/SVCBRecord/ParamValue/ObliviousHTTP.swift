import Foundation
import NIOCore

/// [RFC 9540 Discovery of Oblivious Services via Service Binding Records](https://datatracker.ietf.org/doc/html/rfc9540#name-the-ohttp-svcparamkey)
/// ```text
/// 4.  The "ohttp" SvcParamKey
///
///    The "ohttp" SvcParamKey is used to indicate that a service described
///    in a SVCB RR can be accessed as a target using an associated gateway.
///    The service that is queried by the client hosts one or more Target
///    Resources.
///
///    In order to access the service's Target Resources using Oblivious
///    HTTP, the client needs to send encapsulated messages to the Gateway
///    Resource and the gateway's key configuration (both of which can be
///    retrieved using the method described in Section 6).
///
///    Both the presentation and wire-format values for the "ohttp"
///    parameter MUST be empty.
///
///    Services can include the "ohttp" parameter in the mandatory parameter
///    list if the service is only accessible using Oblivious HTTP.  Marking
///    the "ohttp" parameter as mandatory will cause clients that do not
///    understand the parameter to ignore that SVCB RR.  Including the
///    "ohttp" parameter without marking it mandatory advertises a service
///    that is optionally available using Oblivious HTTP.  Note also that
///    multiple SVCB RRs can be provided to indicate separate
///    configurations.
///
///    The media type to use for encapsulated requests made to a target
///    service depends on the scheme of the SVCB RR.  This document defines
///    the interpretation for the "https" scheme [SVCB] and the "dns" scheme
///    [DNS-SVCB].  Other schemes that want to use this parameter MUST
///    define the interpretation and meaning of the configuration.
/// ```
public struct SVCObliviousHTTP: SVCParamValue {
    public var description: String { "" }  // Has no data

    public static var correspondingKey: SVCParamKey { .ohttp }
    public static var name: String { "ohttp" }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard length == 0 else {
            throw DNSMessageError.invalidFormat(field: "SVC ObliviousHTTP", reason: "length must be 0")
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
