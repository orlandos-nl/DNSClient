import NIO

extension ByteBuffer {
    mutating func write(_ header: DNSMessageHeader) {
        writeInteger(header.id, endianness: .big)
        writeInteger(header.options.rawValue, endianness: .big)
        writeInteger(header.questionCount, endianness: .big)
        writeInteger(header.answerCount, endianness: .big)
        writeInteger(header.authorityCount, endianness: .big)
        writeInteger(header.additionalRecordCount, endianness: .big)
    }

    mutating func readHeader() -> DNSMessageHeader? {
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

    mutating func readLabels() -> [DNSLabel]? {
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

    mutating func readQuestion() -> QuestionSection? {
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

    mutating func readRecord() -> Record? {
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
        default:
            break
        }

        guard let other = make(ByteBuffer.self) else {
            return nil
        }
        
        return .other(other)
    }

    mutating func readRawRecord() -> ResourceRecord<ByteBuffer>? {
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
}
