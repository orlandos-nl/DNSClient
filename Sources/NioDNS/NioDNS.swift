import NIO

class NioDNS {

    deinit {
        _ = channel.close(mode: .all)
    }

    let channel: Channel
    let host: String

    public static func connect(on group: EventLoopGroup, host: String) -> EventLoopFuture<NioDNS> {
        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer { channel in
                return NioDNS.initialize(pipeline: channel.pipeline, hostname: host)
            }

        return bootstrap.bind(host: "0.0.0.0", port: 0).map { channel in
            return NioDNS(channel: channel, host: host)
        }
    }

    init(channel: Channel, host: String) {
        self.channel = channel
        self.host = host
    }
    
    func sendMessage(_ message: Message) {
        try! channel.writeAndFlush(AddressedEnvelope(remoteAddress: SocketAddress(ipAddress: host, port: 53), data: message), promise: nil)
    }

    static func initialize(pipeline: ChannelPipeline, hostname: String) -> EventLoopFuture<Void> {
        /*var handlers: [ChannelHandler] = []
        func addNext() {
            guard handlers.count > 0 else {
                promise.succeed(result: ())
                return
            }

            let handler = handlers.removeFirst()

            pipeline.add(handler: handler).whenSuccess {
                addNext()
            }
        }
        addNext()*/
        return pipeline.add(handler: DNSDecoder()).then {
            pipeline.add(handler: DNSEncoder())
        }
    }
}

fileprivate let endianness = Endianness.big

private final class DNSEncoder: ChannelOutboundHandler {
    typealias OutboundIn = AddressedEnvelope<Message>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    
    func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = self.unwrapOutboundIn(data)
        let message = data.data
        var out = ctx.channel.allocator.buffer(capacity: 512)
        
        let header = message.header
        
        out.write(header)
        
        for question in message.questions {
            for label in question.labels {
                out.write(integer: label.length, endianness: endianness)
                out.write(bytes: label.label)
            }
            
            out.write(integer: 0, endianness: endianness, as: UInt8.self)
            out.write(integer: question.type.rawValue, endianness: endianness)
            out.write(integer: question.questionClass.rawValue, endianness: endianness)
        }
        
        ctx.write(self.wrapOutboundOut(AddressedEnvelope(remoteAddress: data.remoteAddress, data: out)), promise: promise)
    }
}

extension ByteBuffer {
    mutating func write(_ header: MessageHeader) {
        write(integer: header.id, endianness: endianness)
        write(integer: header.options.rawValue, endianness: endianness)
        write(integer: header.questionCount, endianness: endianness)
        write(integer: header.answerCount, endianness: endianness)
        write(integer: header.authorityCount, endianness: endianness)
        write(integer: header.additionalRecordCount, endianness: endianness)
    }
    
    mutating func readHeader() -> MessageHeader? {
        guard
            let id = readInteger(endianness: endianness, as: UInt16.self),
            let options = readInteger(endianness: endianness, as: UInt16.self),
            let questionCount = readInteger(endianness: endianness, as: UInt16.self),
            let answerCount = readInteger(endianness: endianness, as: UInt16.self),
            let authorityCount = readInteger(endianness: endianness, as: UInt16.self),
            let additionalRecordCount = readInteger(endianness: endianness, as: UInt16.self)
        else {
            return nil
        }
        
        return MessageHeader(
            id: id,
            options: MessageOptions(rawValue: options),
            questionCount: questionCount,
            answerCount: answerCount,
            authorityCount: authorityCount,
            additionalRecordCount: additionalRecordCount
        )
    }
    
    mutating func readLabels() -> [QuestionLabel]? {
        var labels = [QuestionLabel]()
        
        while let length = readInteger(endianness: endianness, as: UInt8.self) {
            if length == 0 {
                labels.append("")
                
                return labels
            } else if length >= 64 {
                guard length & 0b11000000 == 0b11000000 else {
                    return nil
                }
                
                moveReaderIndex(to: readerIndex &- 1)
                
                guard
                    var offset = self.readInteger(endianness: endianness, as: UInt16.self)
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
                
                labels.append(QuestionLabel(bytes: bytes))
            }
        }
        
        return nil
    }
    
    mutating func readQuestion() -> QuestionSection? {
        guard let labels = readLabels() else {
            return nil
        }
        
        guard
            let typeNumber = readInteger(endianness: endianness, as: UInt16.self),
            let classNumber = readInteger(endianness: endianness, as: UInt16.self),
            let type = QuestionType(rawValue: typeNumber),
            let dataClass = DataClass(rawValue: classNumber)
        else {
            return nil
        }
        
        return QuestionSection(labels: labels, type: type, questionClass: dataClass)
    }
    
    mutating func readRecord() -> ResourceRecord? {
        guard
            let labels = readLabels(),
            let typeNumber = readInteger(endianness: .big, as: UInt16.self),
            let classNumber = readInteger(endianness: .big, as: UInt16.self),
            let type = ResourceType(rawValue: typeNumber),
            let dataClass = DataClass(rawValue: classNumber),
            let ttl = readInteger(endianness: endianness, as: UInt32.self),
            let dataLength = readInteger(endianness: endianness, as: UInt16.self),
            let data = readBytes(length: Int(dataLength))
        else {
            return nil
        }
        
        return ResourceRecord(
            domainName: labels,
            dataType: type,
            dataClass: dataClass,
            ttl: ttl,
            resourceDataLength: dataLength,
            resourceData: ResourceData(data: data)
        )
    }
}

struct ProtocolError: Error {}

private final class DNSDecoder: ChannelInboundHandler {
    public typealias InboundIn = AddressedEnvelope<ByteBuffer>
    
    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        var buffer = envelope.data
        
        guard let header = buffer.readHeader() else {
            ctx.fireErrorCaught(ProtocolError())
            return
        }
        
        var questions = [QuestionSection]()
        
        for _ in 0..<header.questionCount {
            guard let question = buffer.readQuestion() else {
                ctx.fireErrorCaught(ProtocolError())
                return
            }
            
            questions.append(question)
        }
        
        var records = [ResourceRecord]()
        
        for _ in 0..<header.answerCount {
            guard let record = buffer.readRecord() else {
                ctx.fireErrorCaught(ProtocolError())
                return
            }
            
            records.append(record)
        }
        
        print(header)
        print(questions)
        print(records)
    }
}
