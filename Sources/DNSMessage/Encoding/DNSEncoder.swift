public import NIOCore

public struct DNSEncoder {
    public var buffer: ByteBuffer
    private var namePointers: [(name: DNSName, offset: UInt16)]
    private var nameEncoding: DNSNameEncoding
    private var resetOnNextWrite: Bool = false

    /// Creates a new DNS encoder with the specified name encoding.
    ///
    /// - Parameter nameEncoding: The encoding strategy for domain names. Defaults to `.compressed`
    ///   for optimal message size. Use `.uncompressed` when compression is not desired, or
    ///   `.uncompressedLowercase` for canonical form encoding.
    public init(nameEncoding: DNSNameEncoding = .compressed) {
        self.buffer = ByteBuffer()
        self.buffer.reserveCapacity(1024)

        self.nameEncoding = nameEncoding
        self.namePointers = []
    }

    public mutating func flush() -> ByteBuffer {
        self.resetOnNextWrite = true
        return self.buffer
    }

    /// Temporarily changes the name encoding strategy for the duration of the given closure.
    ///
    /// This method allows you to override the encoder's current name encoding strategy
    /// for a specific operation. The encoding is automatically restored when the closure
    /// completes, even if an error is thrown.
    ///
    /// The new encoding is combined with the current encoding using the strictest option
    /// (max value), ensuring that stricter encoding requirements are never relaxed.
    ///
    /// - Parameters:
    ///   - newEncoding: The temporary encoding strategy to use
    ///   - body: A closure that performs encoding operations with the temporary strategy
    /// - Returns: The return value from the closure
    /// - Throws: Any error thrown by the closure
    public mutating func withNameEncoding(
        newEncoding: DNSNameEncoding,
        body: (inout DNSEncoder) throws -> Int
    ) rethrows -> Int {
        let oldEncoding = self.nameEncoding
        self.nameEncoding = max(oldEncoding, newEncoding)  // Use the strictest option.
        defer {
            self.nameEncoding = oldEncoding
        }

        return try body(&self)
    }

    /// Automatically encodes a UInt16 length prefix followed by data from the passed function.
    ///
    /// Writes a 2-byte length field followed by the data written by the closure. The length
    /// is calculated automatically based on the number of bytes the closure writes. This is
    /// commonly used for DNS RDATA fields and other length-prefixed structures.
    ///
    /// The closure receives a mutable DNSEncoder reference, allowing access to DNS-specific
    /// encoding features like name compression and nested length-prefixed structures.
    public mutating func writeLengthPrefixed(
        _ writeFunction: (inout DNSEncoder) throws -> Int
    ) throws -> Int {
        // Store position where length will be written
        let lengthOffset = self.buffer.writerIndex

        // Write placeholder for length field (2 bytes for UInt16)
        var written = self.buffer.writeInteger(UInt16(0))

        // Write the actual data and capture its length
        let dataLength = try writeFunction(&self)
        written += dataLength

        // Remember current position (end of data)
        let endOffset = self.buffer.writerIndex

        // Go back and overwrite placeholder with actual data length
        self.buffer.moveWriterIndex(to: lengthOffset)

        guard let length = UInt16(exactly: dataLength) else {
            throw ByteBuffer.LengthPrefixError.messageLengthDoesNotFitExactlyIntoRequiredIntegerFormat
        }

        _ = self.buffer.writeInteger(length)

        // Restore writer position to end of data
        self.buffer.moveWriterIndex(to: endOffset)

        return written
    }

    /// Writes a domain name using the configured encoding strategy.
    ///
    /// Domain names in DNS messages can be encoded in three ways:
    /// - **Compressed**: Uses pointer compression to reduce message size (default)
    /// - **Uncompressed**: Full label sequence without compression
    /// - **Uncompressed Lowercase**: Full sequence with labels converted to lowercase
    ///
    /// When compression is enabled, the encoder automatically detects repeated name suffixes
    /// and replaces them with 2-byte pointers, significantly reducing message size for
    /// messages containing many names with common suffixes.
    ///
    /// - Parameter name: The domain name to write
    /// - Returns: The number of bytes written to the buffer
    /// - Throws: DNS encoding errors if name compression fails
    ///
    /// ## Compression Example
    /// For names "mail.example.com" and "www.example.com", the second name would reference
    /// the "example.com" suffix from the first name using a compression pointer.
    public mutating func writeDNSName(_ name: DNSName) throws -> Int {
        var written = 0
        var name = name

        switch self.nameEncoding {
        case .uncompressedLowercase:
            name.toLowercase()
            fallthrough
        case .uncompressed:
            for label in name {
                written += try self.buffer.writeLengthPrefixed(as: UInt8.self) { buffer in
                    buffer.writeBytes(label.bytes)
                }
            }
        case .compressed:
            // RFC 3597 Section 7: DNSSEC canonical form requires downcasing of embedded domain names
            // for RR types published before RFC 3597 (NS, MD, MF, CNAME, SOA, MB, MG, MR, PTR,
            // HINFO, MINFO, MX, RP, AFSDB, RT, SIG, PX, NXT, NAPTR, KX, SRV, DNAME, A6).
            // This ensures correctness of DNSSEC signatures when case distinctions are lost due to compression.
            name.toLowercase()
            for i in 0..<name.count {
                let currName = name[i...]

                if let index = self.getNamePointer(name: currName) {
                    written += self.buffer.writeInteger(UInt16(0xC000) | index)
                    return written
                } else {
                    self.addNamePointer(name: currName, offset: self.buffer.writerIndex)
                    written += try self.buffer.writeLengthPrefixed(as: UInt8.self) { buffer in
                        buffer.writeBytes(name.labels[i].bytes)
                    }
                }
            }
        default:
            // This should never happen as DNSNameEncoding cases are exhaustive.
            preconditionFailure("Unknown DNS name encoding: \(nameEncoding.rawValue)")
        }

        written += self.buffer.writeInteger(UInt8(0))
        return written
    }

    /// Writes a character-string to the buffer with length prefix.
    /// A character-string is a single length octet followed by that number of characters.
    /// Character-strings can be up to 255 characters in length (not including the length octet).
    /// - Parameter characterString: The CharacterString to write
    /// - Returns: The number of bytes written (data length + 1 for length prefix)
    /// - Throws: DNSMessageError if data exceeds 255 bytes
    public mutating func writeCharacterString(_ characterString: DNSCharacterString) throws -> Int {
        try buffer.writeLengthPrefixed(as: UInt8.self) { buffer in
            buffer.writeBytes(characterString.bytes)
        }
    }

    public mutating func writeDNSMessage(_ message: DNSMessage) throws -> Int {
        self.clearIfNeeded()

        var written = 0

        var header = message.header
        header.questionCount = UInt16(message.questions.count)
        header.answerCount = UInt16(message.answers.count)
        header.authorityCount = UInt16(message.authorities.count)
        header.additionalDataCount = UInt16(message.additionalData.count)

        written += self.writeDNSHeader(header)

        for question in message.questions {
            written += try self.writeDNSQuestion(question)
        }

        for answer in message.answers {
            written += try self.writeDNSRecord(answer)
        }

        for authority in message.authorities {
            written += try self.writeDNSRecord(authority)
        }

        for data in message.additionalData {
            written += try self.writeDNSRecord(data)
        }

        return written
    }

    package init(buffer: ByteBuffer, nameEncoding: DNSNameEncoding = .compressed) {
        self.buffer = buffer
        self.nameEncoding = nameEncoding
        self.namePointers = []
    }

    private mutating func writeDNSHeader(_ header: DNSHeader) -> Int {
        var written = 0
        var completeFlags = header.flags

        completeFlags.encodeOpcode(header.opcode)
        completeFlags.encodeResponseCode(header.responseCode)

        written += self.buffer.writeInteger(header.id)
        written += self.buffer.writeInteger(completeFlags.rawValue)
        written += self.buffer.writeInteger(header.questionCount)
        written += self.buffer.writeInteger(header.answerCount)
        written += self.buffer.writeInteger(header.authorityCount)
        written += self.buffer.writeInteger(header.additionalDataCount)

        return written
    }

    private mutating func writeDNSQuestion(_ question: DNSQuestion) throws -> Int {
        var written = 0

        written += try self.writeDNSName(question.name)
        written += self.buffer.writeInteger(question.type.rawValue)
        written += self.buffer.writeInteger(question.questionClass.rawValue)

        return written
    }

    private mutating func writeDNSRecord(_ record: DNSRecord) throws -> Int {
        var written = 0

        // Write the DNS resource record header fields (RFC 1035 Section 3.2.1)
        written += try self.writeDNSName(record.name)  // NAME: domain name
        written += self.buffer.writeInteger(record.rrType.rawValue)  // TYPE: 16-bit record type
        written += self.buffer.writeInteger(record.recordClass.rawValue)  // CLASS: 16-bit class code
        written += self.buffer.writeInteger(record.ttl)  // TTL: 32-bit time to live

        written += try self.writeLengthPrefixed { encoder in
            try encoder.writeRData(record)
        }

        return written
    }

    private mutating func writeRData(_ record: DNSRecord) throws -> Int {
        // Get encoding from registered type, fallback to standard if not registered
        let recordType = DNSResourceType.registeredType(for: record.rrType)
        let encoding: DNSRDataEncoding = recordType.encoding

        return try self.withNameEncoding(newEncoding: encoding.toNameEncoding()) { encoder in
            try record.rData.write(encoder: &encoder)
        }
    }

    private mutating func addNamePointer(name: DNSName, offset: Int) {
        precondition(offset <= UInt16.max)
        precondition(offset >= UInt16.min)
        // DNS compression pointers use 14 bits for the offset (remaining bits after the 11 prefix),
        // so offsets larger than 0x3FFF (16383) cannot be encoded and are not useful for compression.
        if offset <= 0x3FFF {
            self.namePointers.append((name: name, offset: UInt16(offset)))
        }
    }

    private func getNamePointer(name: DNSName) -> UInt16? {
        for (storedName, offset) in self.namePointers {
            if storedName == name {
                return offset
            }
        }

        return nil
    }

    private mutating func clearIfNeeded() {
        if self.resetOnNextWrite {
            self.buffer.clear()
            self.namePointers = []
            self.resetOnNextWrite = false
        }
    }
}
