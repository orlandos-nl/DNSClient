import NIO

/// A DNS SRV record. This is used to specify the location of a service.
public struct SRVRecord: DNSResource {
    /// The priority of this record. Lower values are preferred. This is used to balance load between multiple servers. If two records have the same priority, the weight is used to balance load.
    public let priority: UInt16

    /// The weight of this record. Higher values are preferred. This is used to balance load between multiple servers. If two records have the same priority, the weight is used to balance load.
    public let weight: UInt16

    /// The port of the service.
    public let port: UInt16

    /// The domain name of the service. This can be used to resolve the IP address of the service.
    public let domainName: [DNSLabel]

    public init(priority: UInt16, weight: UInt16, port: UInt16, domainName: [DNSLabel]) {
        self.priority = priority
        self.weight = weight
        self.port = port
        self.domainName = domainName
    }

    public init(priority: UInt16, weight: UInt16, port: UInt16, domainName: String) {
        self.priority = priority
        self.weight = weight
        self.port = port
        self.domainName = domainName
            .split(separator: ".")
            .map(DNSLabel.init)
    }

    public static func read(from buffer: inout ByteBuffer, length: Int) -> SRVRecord? {
        guard
            let priority = buffer.readInteger(endianness: .big, as: UInt16.self),
            let weight = buffer.readInteger(endianness: .big, as: UInt16.self),
            let port = buffer.readInteger(endianness: .big, as: UInt16.self),
            let domainName = buffer.readLabels()
        else {
            return nil
        }

        return SRVRecord(priority: priority, weight: weight, port: port, domainName: domainName)
    }

    public func write(into buffer: inout ByteBuffer, labelIndices: inout [String: UInt16]) -> Int {
        var length = buffer.writeInteger(priority, endianness: .big)
        length += buffer.writeInteger(weight, endianness: .big)
        length += buffer.writeInteger(port, endianness: .big)
        return length + buffer.writeCompressedLabels(domainName, labelIndices: &labelIndices)
    }
}
