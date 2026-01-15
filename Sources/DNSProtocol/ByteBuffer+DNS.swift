import NIO

extension ByteBuffer {
    public mutating func write(_ header: DNSMessageHeader) {
        writeInteger(header.id, endianness: .big)
        writeInteger(header.options.rawValue, endianness: .big)
        writeInteger(header.questionCount, endianness: .big)
        writeInteger(header.answerCount, endianness: .big)
        writeInteger(header.authorityCount, endianness: .big)
        writeInteger(header.additionalRecordCount, endianness: .big)
    }

    public mutating func readHeader() -> DNSMessageHeader? {
        guard
            let id = readInteger(endianness: .big, as: UInt16.self),
            let options = readInteger(endianness: .big, as: UInt16.self),
            let questionCount = readInteger(endianness: .big, as: UInt16.self),
            let answerCount = readInteger(endianness: .big, as: UInt16.self),
            let authorityCount = readInteger(endianness: .big, as: UInt16.self),
            let additionalRecordCount = readInteger(endianness: .big, as: UInt16.self)
            else {
                return nil
        }

        return DNSMessageHeader(
            id: id,
            options: MessageOptions(rawValue: options),
            questionCount: questionCount,
            answerCount: answerCount,
            authorityCount: authorityCount,
            additionalRecordCount: additionalRecordCount
        )
    }

    public mutating func readLabels() -> [DNSLabel]? {
        var labels = [DNSLabel]()

        while let length = readInteger(endianness: .big, as: UInt8.self) {
            if length == 0 {
                labels.append("")

                return labels
            } else if length >= 64 {
                guard length & 0b11000000 == 0b11000000 else {
                    return nil
                }

                moveReaderIndex(to: readerIndex - 1)

                guard
                    var offset = self.readInteger(endianness: .big, as: UInt16.self)
                else {
                    return nil
                }

                offset = offset & 0b00111111_11111111

                guard offset >= 0, offset <= writerIndex else {
                    return nil
                }

                let oldReaderIndex = self.readerIndex
                self.moveReaderIndex(to: Int(offset))

                guard let referencedLabels = readLabels() else {
                    return nil
                }

                labels.append(contentsOf: referencedLabels)
                self.moveReaderIndex(to: oldReaderIndex)
                return labels
            } else {
                guard let bytes = readBytes(length: Int(length)) else {
                    return nil
                }

                labels.append(DNSLabel(bytes: bytes))
            }
        }

        return labels
    }

    public mutating func readQuestion() -> QuestionSection? {
        guard let labels = readLabels() else {
            return nil
        }

        guard
            let typeNumber = readInteger(endianness: .big, as: UInt16.self),
            let classNumber = readInteger(endianness: .big, as: UInt16.self),
            let type = QuestionType(rawValue: typeNumber),
            let dataClass = DataClass(rawValue: classNumber)
            else {
                return nil
        }

        return QuestionSection(labels: labels, type: type, questionClass: dataClass)
    }

    public mutating func writeRecord<RecordType: DNSResource>(
        _ record: ResourceRecord<RecordType>,
        labelIndices: inout [String: UInt16]
    ) throws {
        writeCompressedLabels(record.domainName, labelIndices: &labelIndices)
        writeInteger(record.dataType)
        writeInteger(record.dataClass)
        writeInteger(record.ttl)

        try writeLengthPrefixed(as: UInt16.self) { buffer in
            record.resource.write(into: &buffer, labelIndices: &labelIndices)
        }
    }

    public mutating func writeAnyRecord(
        _ record: Record,
        labelIndices: inout [String: UInt16]
    ) throws {
        switch record {
        case .aaaa(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        case .a(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        case .txt(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        case .cname(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        case .srv(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        case .mx(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        case .ptr(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        case .ns(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        case .soa(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        case .other(let resourceRecord):
            try writeRecord(resourceRecord, labelIndices: &labelIndices)
        }
    }

    public mutating func readRecord() -> Record? {
        guard
            let labels = readLabels(),
            let typeNumber = readInteger(endianness: .big, as: UInt16.self),
            let classNumber = readInteger(endianness: .big, as: UInt16.self),
            let ttl = readInteger(endianness: .big, as: UInt32.self),
            let dataLength = readInteger(endianness: .big, as: UInt16.self)
            else {
                return nil
        }

        let newIndex = readerIndex + Int(dataLength)

        guard newIndex <= writerIndex else {
            return nil
        }

        defer {
            moveReaderIndex(to: newIndex)
        }

        func make<Resource>(_ resource: Resource.Type) -> ResourceRecord<Resource>? {
            guard let resource = Resource.read(from: &self, length: Int(dataLength)) else {
                return nil
            }

            return ResourceRecord(
                domainName: labels,
                dataType: typeNumber,
                dataClass: classNumber,
                ttl: ttl,
                resource: resource
            )
        }

        guard let recordType = DNSResourceType(rawValue: typeNumber) else {
            guard let other = make(ByteBuffer.self) else { return nil }
            return .other(other)
        }

        switch recordType {
        case .a:
            guard let a = make(ARecord.self) else {
                return nil
            }

            return .a(a)
        case .aaaa:
            guard let aaaa = make(AAAARecord.self) else {
                return nil
            }

            return .aaaa(aaaa)
        case .txt:
            guard let txt = make(TXTRecord.self) else {
                return nil
            }

            return .txt(txt)
        case .srv:
            guard let srv = make(SRVRecord.self) else {
                return nil
            }

            return .srv(srv)
        case .mx:
            guard let mx = make(MXRecord.self) else {
                return nil
            }

            return .mx(mx)
        case .cName:
            guard let cname = make(CNAMERecord.self) else {
                return nil
            }

            return .cname(cname)
        case .ptr:
            guard let ptr = make(PTRRecord.self) else {
                return nil
            }

            return .ptr(ptr)
        case .ns:
            guard let ns = make(NSRecord.self) else {
                return nil
            }

            return .ns(ns)
        case .soa:
                guard let soa = make(SOARecord.self) else {
                    return nil
                }

            return .soa(soa)
        default:
            break
        }

        guard let other = make(ByteBuffer.self) else {
            return nil
        }

        return .other(other)
    }

    public mutating func readRawRecord() -> ResourceRecord<ByteBuffer>? {
        guard
            let labels = readLabels(),
            let typeNumber = readInteger(endianness: .big, as: UInt16.self),
            let classNumber = readInteger(endianness: .big, as: UInt16.self),
            let ttl = readInteger(endianness: .big, as: UInt32.self),
            let dataLength = readInteger(endianness: .big, as: UInt16.self),
            let resource = ByteBuffer.read(from: &self, length: Int(dataLength))
            else {
                return nil
        }

        let record = ResourceRecord(
            domainName: labels,
            dataType: typeNumber,
            dataClass: classNumber,
            ttl: ttl,
            resource: resource
        )

        self.moveReaderIndex(forwardBy: Int(dataLength))
        return record
    }

    /// Either write label index or list of labels
    @discardableResult
    public mutating func writeCompressedLabels(_ labels: [DNSLabel], labelIndices: inout [String: UInt16]) -> Int {
        var written = 0
        var labels = labels
        while !labels.isEmpty {
            // Build key for the full remaining sequence including current label
            let fullKey = labels.string

            // Empty key means we only have the terminating empty label left
            if fullKey.isEmpty {
                // Write terminating null byte
                written += writeInteger(UInt8(0))
                return written
            }

            // Check if we can compress the entire remaining sequence
            if let labelIndex = labelIndices[fullKey] {
                // Write compression pointer for the entire remaining sequence
                written += writeInteger(labelIndex | 0xc000)
                return written
            }

            // No compression available - write this label and continue
            let label = labels.removeFirst()

            // Store position for this label sequence BEFORE writing
            labelIndices[fullKey] = numericCast(writerIndex)

            // Write the label
            written += writeInteger(UInt8(label.label.count))
            written += writeBytes(label.label)
        }
        // write end of labels (shouldn't normally reach here with well-formed labels)
        written += writeInteger(UInt8(0))
        return written
    }

    /// write labels into DNS packet
    @discardableResult
    public mutating func writeLabels(_ labels: [DNSLabel]) -> Int {
        var written = 0
        for label in labels {
            written += writeInteger(UInt8(label.label.count))
            written += writeBytes(label.label)
        }

        return written
    }

    public func labelsSize(_ labels: [DNSLabel]) -> Int {
        return labels.reduce(0, { $0 + 2 + $1.label.count })
    }
}
