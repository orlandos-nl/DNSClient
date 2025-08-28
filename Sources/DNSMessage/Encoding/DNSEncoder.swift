import NIOCore

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

    package init(buffer: ByteBuffer, nameEncoding: DNSNameEncoding = .compressed) {
        self.buffer = buffer
        self.nameEncoding = nameEncoding
        self.namePointers = []
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
