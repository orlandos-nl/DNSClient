import NIO

class NioDNS: Resolver {
    let channel: Channel
    let host: String
    let dnsDecoder: DNSDecoder
    var loop: EventLoop {
        return channel.eventLoop
    }

    var messageID: UInt16 = 0

    public func initiateAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        messageID = messageID &+ 1
        let header = MessageHeader(id: messageID, options: [.standardQuery, .recursionDesired], questionCount: 1, answerCount: 0, authorityCount: 0, additionalRecordCount: 0)
        let labels = host.split(separator: ".").map(String.init).map(QuestionLabel.init)
        let question = QuestionSection(labels: labels, type: .a, questionClass: .internet)
        let message = Message(header: header, questions: [question], answers: [], authorities: [], additionalData: [])

        let promise: EventLoopPromise<Message> = loop.newPromise()
        dnsDecoder.messageCache[messageID] = promise
        self.sendMessage(message)

        return promise.futureResult.map { message in
            return message.answers.compactMap { answer in
                guard answer.resourceDataLength == 4 else {
                    return nil
                }

                let ipAddress = answer.resourceData.data.withUnsafeBytes { buffer in
                    return buffer.bindMemory(to: UInt32.self).baseAddress!.pointee
                }

                let sockaddr = sockaddr_in(sin_family: sa_family_t(AF_INET), sin_port: in_port_t(port), sin_addr: in_addr(s_addr: ipAddress), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
                return SocketAddress(sockaddr, host: host)
            }
        }
    }

    public func initiateAAAAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        messageID = messageID &+ 1
        let header = MessageHeader(id: messageID, options: [.standardQuery, .recursionDesired], questionCount: 1, answerCount: 0, authorityCount: 0, additionalRecordCount: 0)
        let labels = host.split(separator: ".").map(String.init).map(QuestionLabel.init)
        let question = QuestionSection(labels: labels, type: .aaaa, questionClass: .internet)
        let message = Message(header: header, questions: [question], answers: [], authorities: [], additionalData: [])

        let promise: EventLoopPromise<Message> = loop.newPromise()
        dnsDecoder.messageCache[messageID] = promise
        self.sendMessage(message)

        return promise.futureResult.map { message in
            return message.answers.compactMap { answer in
                 guard answer.resourceDataLength == 16 else {
                     return nil
                 }

                let ipAddress = answer.resourceData.data.withUnsafeBytes { buffer in
                    // sin6_addr.in6_addr type needs to be in6_addr.__Unnamed_union___in6_u
                    return buffer.bindMemory(to: in6_addr.__Unnamed_union___in6_u.self).baseAddress!.pointee
                }

                let scopeID: UInt32 = 0
                let flowinfo: UInt32 = 0
                let sockaddr = sockaddr_in6(sin6_family: sa_family_t(AF_INET6), sin6_port: in_port_t(port), sin6_flowinfo: flowinfo, sin6_addr: in6_addr(__in6_u: ipAddress), sin6_scope_id: scopeID)
                return SocketAddress(sockaddr, host: host)
            }
        }
    }

    public func cancelQueries() {
        for (id, promise) in dnsDecoder.messageCache {
            dnsDecoder.messageCache[id] = nil
            promise.fail(error: CancelError())
        }
    }

    public static func connect(on group: EventLoopGroup, host: String) -> EventLoopFuture<NioDNS> {
        let dnsDecoder = DNSDecoder()

        let bootstrap = DatagramBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.add(handler: dnsDecoder).then {
                    channel.pipeline.add(handler: DNSEncoder())
                }
            }

        return bootstrap.bind(host: "0.0.0.0", port: 0).map { channel in
            return NioDNS(channel: channel, host: host, decoder: dnsDecoder)
        }
    }

    deinit {
        _ = channel.close(mode: .all)
    }

    init(channel: Channel, host: String, decoder: DNSDecoder) {
        self.channel = channel
        self.host = host
        self.dnsDecoder = decoder
    }
    
    func sendMessage(_ message: Message) {
        try! channel.writeAndFlush(AddressedEnvelope(remoteAddress: SocketAddress(ipAddress: host, port: 53), data: message), promise: nil)
    }
}

fileprivate let endianness = Endianness.big

struct CancelError: Error {}
struct ProtocolError: Error {}

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
            let typeNumber = readInteger(endianness: endianness, as: UInt16.self),
            let classNumber = readInteger(endianness: endianness, as: UInt16.self),
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

final class DNSEncoder: ChannelOutboundHandler {
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

final class DNSDecoder: ChannelInboundHandler {
    var messageCache = [UInt16: EventLoopPromise<Message>]()

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

        func resourceRecords(count: UInt16) -> [ResourceRecord] {
            var records = [ResourceRecord]()

            for _ in 0..<count {
                guard let record = buffer.readRecord() else {
                    ctx.fireErrorCaught(ProtocolError())
                    return []
                }

                records.append(record)
            }

            return records
        }

        messageCache[header.id]?.succeed(result: Message(
                header: header,
                questions: questions,
                answers: resourceRecords(count: header.answerCount),
                authorities: resourceRecords(count: header.authorityCount),
                additionalData: resourceRecords(count: header.additionalRecordCount)
        ))
        /*print(header)
        print(questions)
        print(resourceRecords(count: header.answerCount))
        print(resourceRecords(count: header.authorityCount))
        print(resourceRecords(count: header.additionalRecordCount))*/
    }
}
