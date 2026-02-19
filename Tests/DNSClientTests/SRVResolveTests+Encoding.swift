import NIO

#if canImport(Network)
import NIOTransportServices
#endif
@testable import DNSClient

extension ByteBuffer {
    @discardableResult
    mutating func writeLabelsUncompressed(_ labels: [DNSLabel]) -> Int {
        var written = 0
        for label in labels {
            if label.length == 0 {
                written += writeInteger(UInt8(0))
                return written
            }
            written += writeInteger(UInt8(label.label.count))
            written += writeBytes(label.label)
        }
        written += writeInteger(UInt8(0))
        return written
    }

    mutating func writeAnyRecordUncompressed(_ record: Record) throws {
        switch record {
        case .srv(let rr):
            writeLabelsUncompressed(rr.domainName)
            writeInteger(rr.dataType)
            writeInteger(rr.dataClass)
            writeInteger(rr.ttl)
            try writeLengthPrefixed(as: UInt16.self) { buffer in
                var length = buffer.writeInteger(rr.resource.priority)
                length += buffer.writeInteger(rr.resource.weight)
                length += buffer.writeInteger(rr.resource.port)
                length += buffer.writeLabelsUncompressed(rr.resource.domainName)
                return length
            }
        case .a(let rr):
            writeLabelsUncompressed(rr.domainName)
            writeInteger(rr.dataType)
            writeInteger(rr.dataClass)
            writeInteger(rr.ttl)
            try writeLengthPrefixed(as: UInt16.self) { buffer in
                return buffer.writeInteger(rr.resource.address)
            }
        case .aaaa(let rr):
            writeLabelsUncompressed(rr.domainName)
            writeInteger(rr.dataType)
            writeInteger(rr.dataClass)
            writeInteger(rr.ttl)
            try writeLengthPrefixed(as: UInt16.self) { buffer in
                return buffer.writeBytes(rr.resource.address)
            }
        default:
            preconditionFailure("Unsupported record type in SRVResolveTests")
        }
    }
}
