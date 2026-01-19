import NIO

/// TCP frame decoder for DNS messages (2-byte length prefix).
public final class UInt16FrameDecoder: ByteToMessageDecoder {
    public typealias InboundOut = ByteBuffer

    public init() {}

    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        var readBuffer = buffer
        guard
            let size: UInt16 = readBuffer.readInteger(),
            let slice = readBuffer.readSlice(length: Int(size))
        else {
            return .needMoreData
        }

        buffer.moveReaderIndex(to: readBuffer.readerIndex)
        context.fireChannelRead(wrapInboundOut(slice))
        return .continue
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        try decode(context: context, buffer: &buffer)
    }
}

/// TCP frame encoder for DNS messages (2-byte length prefix).
public final class UInt16FrameEncoder: MessageToByteEncoder {
    public typealias OutboundIn = ByteBuffer

    public init() {}

    public func encode(data: ByteBuffer, out: inout ByteBuffer) throws {
        try out.writeLengthPrefixed(as: UInt16.self) { out in
            out.writeImmutableBuffer(data)
        }
    }
}

/// Encodes DNS messages to ByteBuffer.
public enum DNSMessageEncoder {
    public static func encodeMessage(
        _ message: Message,
        allocator: ByteBufferAllocator,
        labelIndices: inout [String: UInt16]
    ) throws -> ByteBuffer {
        var out = allocator.buffer(capacity: 512)

        let header = message.header

        out.write(header)

        for question in message.questions {
            out.writeCompressedLabels(question.labels, labelIndices: &labelIndices)

            out.writeInteger(question.type.rawValue, endianness: .big)
            out.writeInteger(question.questionClass.rawValue, endianness: .big)
        }

        for answer in message.answers {
            try out.writeAnyRecord(answer, labelIndices: &labelIndices)
        }

        for authority in message.authorities {
            try out.writeAnyRecord(authority, labelIndices: &labelIndices)
        }

        for additionalData in message.additionalData {
            try out.writeAnyRecord(additionalData, labelIndices: &labelIndices)
        }

        return out
    }
}

/// Parses DNS messages from ByteBuffer.
public enum DNSMessageDecoder {
    public static func parse(_ buffer: ByteBuffer) throws -> Message {
        var buffer = buffer

        guard let header = buffer.readHeader() else {
            throw DNSProtocolError()
        }

        var questions = [QuestionSection]()

        for _ in 0..<header.questionCount {
            guard let question = buffer.readQuestion() else {
                throw DNSProtocolError()
            }

            questions.append(question)
        }

        func resourceRecords(count: UInt16) throws -> [Record] {
            var records = [Record]()

            for _ in 0..<count {
                guard let record = buffer.readRecord() else {
                    throw DNSProtocolError()
                }

                records.append(record)
            }

            return records
        }

        let answers = try resourceRecords(count: header.answerCount)
        let authorities = try resourceRecords(count: header.authorityCount)
        let additionalData = try resourceRecords(count: header.additionalRecordCount)

        return Message(
            header: header,
            questions: questions,
            answers: answers,
            authorities: authorities,
            additionalData: additionalData
        )
    }
}
