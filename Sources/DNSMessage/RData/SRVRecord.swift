import NIOCore

public struct SRVRecord: DNSResourceData {
    public var priority: UInt16
    public var weight: UInt16
    public var port: UInt16
    public var target: DNSName

    public var description: String {
        "\(self.priority) \(self.weight) \(self.port) \(String(describing: self.target))"
    }

    public static var name: String { "SRV" }
    public static var encoding: DNSRDataEncoding { .canonical }
    public static var resourceType: DNSResourceType { .srv }

    public init(priority: UInt16, weight: UInt16, port: UInt16, target: DNSName) {
        self.priority = priority
        self.weight = weight
        self.port = port
        self.target = target
    }

    public init(from decoder: inout DNSDecoder, length: Int) throws {
        guard
            let priority: UInt16 = decoder.buffer.readInteger(),
            let weight: UInt16 = decoder.buffer.readInteger(),
            let port: UInt16 = decoder.buffer.readInteger()
        else {
            throw DNSMessageError.insufficientData(expected: 6, available: decoder.buffer.readableBytes)
        }
        self.priority = priority
        self.weight = weight
        self.port = port
        self.target = DNSName()
        try decoder.readDNSName(name: &self.target)
    }

    public func write(encoder: inout DNSEncoder) throws -> Int {
        var written = 0

        written += encoder.buffer.writeInteger(self.priority)
        written += encoder.buffer.writeInteger(self.weight)
        written += encoder.buffer.writeInteger(self.port)
        written += try encoder.writeDNSName(self.target)

        return written
    }
}
