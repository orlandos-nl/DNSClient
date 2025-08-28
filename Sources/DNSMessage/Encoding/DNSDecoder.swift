import NIOCore

public struct DNSDecoder {
    public var buffer: ByteBuffer

    public init(buffer: ByteBuffer) {
        self.buffer = buffer
    }

    public mutating func readDNSName() throws -> DNSName {
        var name = DNSName()
        while let length = buffer.readInteger(as: UInt8.self) {
            switch length {
            case 0:
                return name
            case 1..<64:
                guard let bytes = buffer.readBytes(length: Int(length)) else {
                    throw DNSMessageError.insufficientData(expected: Int(length), available: buffer.readableBytes)
                }

                try name.append(label: try DNSLabel(bytes: bytes))
            case 64... where length & 0xC0 == 0xC0:
                buffer.moveReaderIndex(to: buffer.readerIndex - 1)

                guard var pointer = buffer.readInteger(as: UInt16.self) else {
                    throw DNSMessageError.insufficientData(expected: 2, available: buffer.readableBytes)
                }

                pointer &= 0x3FFF

                guard pointer < buffer.writerIndex else {
                    throw DNSMessageError.invalidFormat(
                        field: "DNS name pointer",
                        reason: "pointer \(pointer) exceeds buffer size \(buffer.writerIndex)"
                    )
                }

                let currentReaderIndex = buffer.readerIndex
                buffer.moveReaderIndex(to: Int(pointer))

                let referencedName = try self.readDNSName()
                buffer.moveReaderIndex(to: currentReaderIndex)

                try name.append(contentsOf: referencedName)
                return name
            default:
                throw DNSMessageError.unrecognizedLabelCode(length)
            }
        }

        throw DNSMessageError.insufficientData(expected: 1, available: buffer.readableBytes)
    }
}
