/// The type of resource record. This is used to determine the format of the record.
///
/// The official standard list of all Resource Record (RR) Types. [IANA](https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml#dns-parameters-4)
public enum DNSResourceType: UInt16, Sendable {
    /// A request for an IPv4 address
    case a = 1

    /// A request for an authoritative name server
    case ns

    /// A request for a mail destination (Obsolete - see MX)
    case md

    /// A request for a mail destination (Obsolete - see MX)
    case mf

    /// A request for a canonical name for an alias.
    case cName

    /// Marks the start of a zone of authority. This is used for delegation of zones.
    case soa

    /// A request for a mail group member (Obsolete - see MX)
    case mb

    /// A request for a mail group member
    case mg

    /// A request for a mail agent (Obsolete - see MX)
    case mr

    case null

    /// A request for a well known service description.
    case wks

    /// A domain name pointer (ie. in-addr.arpa) for address to name
    case ptr

    /// A request for a canonical name for an alias
    case hInfo

    /// A request for host information
    case mInfo

    /// A request for a mail exchange record
    case mx

    /// A request for a text record. This is used for storing arbitrary text.
    case txt

    /// A request for an IPv6 address
    case aaaa = 28

    /// A request for an SRV record. This is used for service discovery.
    case srv = 33

    // QuestionType exclusive

    /// A request for a transfer of an entire zone
    case axfr = 252

    /// A request for mailbox-related records (MB, MG or MR)
    case mailB = 253

    /// A request for mail agent RRs (Obsolete - see MX)
    case mailA = 254

    /// A request for all records
    case any = 255
}

public typealias QuestionType = DNSResourceType

/// The class of the resource record. This is used to determine the format of the record.
public enum DataClass: UInt16, Sendable {
    /// The Internet
    case internet = 1

    /// The CSNET class (Obsolete - used only for examples in some obsolete RFCs)
    case chaos = 3

    /// The Hesiod class (Obsolete -
    case hesoid = 4
}
