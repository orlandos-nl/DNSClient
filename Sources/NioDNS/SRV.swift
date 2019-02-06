import NIO

public struct SRVData {
    public let priority: UInt16
    public let weight: UInt16
    public let port: UInt16
    public let domainName: [DNSLabel]
    
    init(record: ResourceRecord) throws {
        guard
            var byteBuffer = record.resourceData,
            let priority = byteBuffer.readInteger(endianness: .big, as: UInt16.self),
            let weight = byteBuffer.readInteger(endianness: .big, as: UInt16.self),
            let port = byteBuffer.readInteger(endianness: .big, as: UInt16.self),
            let domainName = byteBuffer.readLabels()
        else {
            throw InvalidSRV()
        }
        
        self.priority = priority
        self.weight = weight
        self.port = port
        self.domainName = domainName
//        guard let priority = byteBuffer.getInteger
    }
}

fileprivate struct InvalidSRV: Error {}
