import NIOCore

public struct DNSDecoder {
    public var buffer: ByteBuffer

    public init(buffer: ByteBuffer) {
        self.buffer = buffer
    }

    /// Reads a character-string from the buffer.
    /// A character-string is a single length octet followed by that number of characters.
    /// Character-strings can be up to 255 characters in length (not including the length octet).
    /// - Returns: The character-string bytes (without the length prefix)
    /// - Throws: DNSMessageError if insufficient data or invalid format
    public mutating func readCharacterString() throws -> [UInt8] {
        guard let length: UInt8 = buffer.readInteger() else {
            throw DNSMessageError.insufficientData(expected: 1, available: buffer.readableBytes)
        }

        guard let data = buffer.readBytes(length: Int(length)) else {
            throw DNSMessageError.insufficientData(
                expected: Int(length),
                available: buffer.readableBytes
            )
        }

        return data
    }

    /// Reads a DNS name from the buffer, handling label compression.
    ///
    /// DNS names consist of length-prefixed labels terminated by a zero-length label.
    /// Supports RFC 1035 name compression where labels can be replaced by 2-byte pointers
    /// to previously encoded names within the same message to reduce size.
    ///
    /// - Parameter name: The DNSName to append decoded labels to
    /// - Throws: DNSMessageError for malformed names, invalid pointers, or insufficient data
    public mutating func readDNSName(name: inout DNSName) throws {
        while let length = buffer.readInteger(as: UInt8.self) {
            switch length {
            case 0:
                return
            case 1..<64:
                guard let bytes = buffer.readBytes(length: Int(length)) else {
                    throw DNSMessageError.insufficientData(expected: Int(length), available: buffer.readableBytes)
                }

                try name.append(label: DNSLabel(bytes: bytes))
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
                try self.readDNSName(name: &name)
                buffer.moveReaderIndex(to: currentReaderIndex)
                return
            default:
                throw DNSMessageError.unrecognizedLabelCode(length)
            }
        }

        throw DNSMessageError.insufficientData(expected: 1, available: buffer.readableBytes)
    }

    /// Reads a complete DNS message from the buffer.
    ///
    /// Decodes the standard DNS message format: header followed by question, answer,
    /// authority, and additional record sections. The header contains counts for each
    /// section which determines how many records to read from each section.
    ///
    /// - Returns: A fully decoded DNSMessage
    /// - Throws: DNSMessageError for malformed messages or insufficient data
    public mutating func readDNSMessage() throws -> DNSMessage {
        let header = try self.readDNSHeader()

        var questions: [DNSQuestion] = []
        var answers: [DNSRecord] = []
        var authorities: [DNSRecord] = []
        var additionalData: [DNSRecord] = []

        for _ in 0..<header.questionCount {
            questions.append(try self.readDNSQuestion())
        }

        for _ in 0..<header.answerCount {
            answers.append(try self.readDNSRecord())
        }

        for _ in 0..<header.authorityCount {
            authorities.append(try self.readDNSRecord())
        }

        for _ in 0..<header.additionalDataCount {
            additionalData.append(try self.readDNSRecord())
        }

        return DNSMessage(
            header: header,
            questions: questions,
            answers: answers,
            authorities: authorities,
            additionalData: additionalData
        )
    }

    private mutating func readDNSHeader() throws -> DNSHeader {
        // Read the fields in order: ID, FLAGS, QDCOUNT, ANCOUNT, NSCOUNT, ARCOUNT
        guard let id = self.buffer.readInteger(as: UInt16.self),
            let rawFlags = self.buffer.readInteger(as: UInt16.self),
            let questionCount = self.buffer.readInteger(as: UInt16.self),
            let answerCount = self.buffer.readInteger(as: UInt16.self),
            let authorityCount = self.buffer.readInteger(as: UInt16.self),
            let additionalDataCount = self.buffer.readInteger(as: UInt16.self)
        else {
            throw DNSMessageError.insufficientData(expected: 12, available: buffer.readableBytes)
        }

        // Create flags with the raw value to extract opcode and response code
        var flags = DNSHeaderFlags(rawValue: rawFlags)

        // Extract opcode and response code from the combined flags field (this cleans the bits)
        let opcode = flags.decodeOpcode()
        let responseCode = flags.decodeResponseCode()

        return DNSHeader(
            id: id,
            flags: flags,
            opcode: opcode,
            responseCode: responseCode,
            questionCount: questionCount,
            answerCount: answerCount,
            authorityCount: authorityCount,
            additionalDataCount: additionalDataCount
        )
    }

    private mutating func readDNSQuestion() throws -> DNSQuestion {
        var name = DNSName()
        try self.readDNSName(name: &name)
        guard
            let typeRaw: UInt16 = self.buffer.readInteger(),
            let questionClassRaw: UInt16 = self.buffer.readInteger()
        else {
            throw DNSMessageError.insufficientData(expected: 4, available: buffer.readableBytes)
        }

        return try DNSQuestion(
            name: name,
            type: .init(rawValue: typeRaw),
            questionClass: .init(rawValue: questionClassRaw)
        )
    }

    private mutating func readDNSRecord() throws -> DNSRecord {
        var name = DNSName()
        try self.readDNSName(name: &name)
        guard
            let rrTypeRaw: UInt16 = self.buffer.readInteger(),
            let dnsClassRaw: UInt16 = self.buffer.readInteger(),
            let ttl: UInt32 = self.buffer.readInteger(),
            let length: UInt16 = self.buffer.readInteger()
        else {
            throw DNSMessageError.insufficientData(expected: 10, available: buffer.readableBytes)
        }

        let recordType = DNSResourceType(rawValue: rrTypeRaw)
        let recordClass = DNSClass(rawValue: dnsClassRaw)

        let recordDataType = DNSResourceType.registeredType(for: recordType)
        // Parse using the registered type or as NULLRecord if it is not registered
        let rdata = try recordDataType.init(from: &self, length: Int(length))

        return try DNSRecord(
            name: name,
            rrType: recordType,
            dnsClass: recordClass,
            ttl: ttl,
            rData: rdata
        )
    }
}
