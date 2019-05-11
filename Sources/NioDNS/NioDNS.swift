import NIO

public final class NioDNS: Resolver {
    let dnsDecoder: DNSDecoder
    let channel: Channel
    let primaryAddress: SocketAddress
    var loop: EventLoop {
        return channel.eventLoop
    }
    // Each query has an ID to keep track of which response belongs to which query
    var messageID: UInt16 = 0
    
    /// Request A records
    ///
    /// - parameters:
    ///     - host: The hostname address to request the records from
    ///     - port: The port to use
    /// - returns: A future of SocketAddresses
    public func initiateAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        let result = self.sendQuery(forHost: host, type: .a)
        
        return result.thenThrowing { message in
            return message.answers.compactMap { answer in
                guard case .a(let record) = answer else {
                    return nil
                }

                return try? record.resource.address.socketAddress(port: port)
            }
        }
    }
    
    /// Request AAAA records
    ///
    /// - parameters:
    ///     - host: The hostname address to request the records from
    ///     - port: The port to use
    /// - returns: A future of SocketAddresses
    public func initiateAAAAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        let result = self.sendQuery(forHost: host, type: .aaaa)
        
        return result.map { message in
            return message.answers.compactMap { answer in
                guard
                    case .aaaa(let record) = answer,
                    record.resource.address.count == 16
                else {
                    return nil
                }

                let address = record.resource.address
                let ipAddress = address.withUnsafeBytes { buffer in
                    // sin6_addr.in6_addr needs to be of type in6_addr.__Unnamed_union___in6_u
                    return buffer.bindMemory(to: in6_addr.__Unnamed_union___u6_addr.self).baseAddress!.pointee
                }
                
                let scopeID: UInt32 = 0 // More info about scope_id/zone_id https://tools.ietf.org/html/rfc6874#page-3
                let flowinfo: UInt32 = 0 // More info about flowinfo https://tools.ietf.org/html/rfc6437#page-4
                #if os(Linux)
                let sockaddr = sockaddr_in6(sin6_family: sa_family_t(AF_INET6), sin6_port: in_port_t(port), sin6_flowinfo: flowinfo, sin6_addr: in6_addr(__u6_addr: ipAddress), sin6_scope_id: scopeID)
                #else
                let size = MemoryLayout<sockaddr_in6>.size
                let sockaddr = sockaddr_in6(sin6_len: numericCast(size), sin6_family: sa_family_t(AF_INET6), sin6_port: in_port_t(port), sin6_flowinfo: flowinfo, sin6_addr: in6_addr(__u6_addr: ipAddress), sin6_scope_id: scopeID)
                #endif
                
                return SocketAddress(sockaddr, host: host)
            }
        }
    }
    
    /// Cancel all queries
    public func cancelQueries() {
        for (id, query) in dnsDecoder.messageCache {
            dnsDecoder.messageCache[id] = nil
            query.promise.fail(error: CancelError())
        }
    }
    
    deinit {
        _ = channel.close(mode: .all)
    }
    
    init(channel: Channel, address: SocketAddress, decoder: DNSDecoder) {
        self.channel = channel
        self.primaryAddress = address
        self.dnsDecoder = decoder
    }
    
    /// Send a question to the dns host
    ///
    /// - parameters:
    ///     - address: The hostname address to request a certain resource from
    ///     - type: The resource you want to request
    ///     - additionalOptions: Additional message options
    /// - returns: A future with the response message
    public func sendQuery(forHost address: String, type: ResourceType, additionalOptions: MessageOptions? = nil) -> EventLoopFuture<Message> {
        messageID = messageID &+ 1
        
        var options: MessageOptions = [.standardQuery, .recursionDesired]
        if let additionalOptions = additionalOptions {
            options.insert(additionalOptions)
        }
        
        let header = MessageHeader(id: messageID, options: options, questionCount: 1, answerCount: 0, authorityCount: 0, additionalRecordCount: 0)
        let labels = address.split(separator: ".").map(String.init).map(DNSLabel.init)
        let question = QuestionSection(labels: labels, type: type, questionClass: .internet)
        let message = Message(header: header, questions: [question], answers: [], authorities: [], additionalData: [])
        
        return send(message)
    }
    
    func send(_ message: Message, to address: SocketAddress? = nil) -> EventLoopFuture<Message> {
        let promise: EventLoopPromise<Message> = loop.newPromise()
        dnsDecoder.messageCache[message.header.id] = SentQuery(message: message, promise: promise)
        
        channel.writeAndFlush(AddressedEnvelope(remoteAddress: address ?? primaryAddress, data: message), promise: nil)
        
        return promise.futureResult
    }
    
    /// Request SRV records from a host
    ///
    /// - parameters:
    ///     - host: Hostname to get the records from
    /// - returns: A future with the resource record
    public func getSRVRecords(from host: String) -> EventLoopFuture<[ResourceRecord<SRVRecord>]> {
        return self.sendQuery(forHost: host, type: .srv).thenThrowing { message in
            return message.answers.compactMap { answer in
                guard case .srv(let record) = answer else {
                    return nil
                }
                
                return record
            }
        }
    }
}

fileprivate let endianness = Endianness.big

struct UnableToParseConfig: Error {}
struct MissingNameservers: Error {}
struct CancelError: Error {}
struct AuthorityNotFound: Error {}
struct ProtocolError: Error {}
struct UnknownQuery: Error {}

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
    
    mutating func readLabels() -> [DNSLabel]? {
        var labels = [DNSLabel]()
        
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
            let typeNumber = readInteger(endianness: endianness, as: UInt16.self),
            let classNumber = readInteger(endianness: endianness, as: UInt16.self),
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
            let typeNumber = readInteger(endianness: endianness, as: UInt16.self),
            let classNumber = readInteger(endianness: endianness, as: UInt16.self),
            let ttl = readInteger(endianness: endianness, as: UInt32.self),
            let dataLength = readInteger(endianness: endianness, as: UInt16.self)
            else {
                return nil
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

        guard let recordType = ResourceType(rawValue: typeNumber) else {
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
        default:
            break
        }

        guard let other = make(ByteBuffer.self) else { return nil }
        return .other(other)
    }
    
    mutating func readRawRecord() -> ResourceRecord<ByteBuffer>? {
        guard
            let labels = readLabels(),
            let typeNumber = readInteger(endianness: endianness, as: UInt16.self),
            let classNumber = readInteger(endianness: endianness, as: UInt16.self),
            let ttl = readInteger(endianness: endianness, as: UInt32.self),
            let dataLength = readInteger(endianness: endianness, as: UInt16.self),
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

struct SentQuery {
    let message: Message
    let promise: EventLoopPromise<Message>
}

final class DNSDecoder: ChannelInboundHandler {
    let group: EventLoopGroup
    var messageCache = [UInt16: SentQuery]()
    var clients = [ObjectIdentifier: NioDNS]()
    weak var mainClient: NioDNS?
    
    init(group: EventLoopGroup) {
        self.group = group
    }
    
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
        
        func resourceRecords(count: UInt16) throws -> [Record] {
            var records = [Record]()
            
            for _ in 0..<count {
                guard let record = buffer.readRecord() else {
                    throw ProtocolError()
                }
                
                records.append(record)
            }
            
            return records
        }
        
        do {
            let message = Message(
                header: header,
                questions: questions,
                answers: try resourceRecords(count: header.answerCount),
                authorities: try resourceRecords(count: header.authorityCount),
                additionalData: try resourceRecords(count: header.additionalRecordCount)
            )
            
            guard let query = messageCache[header.id] else {
                throw UnknownQuery()
            }
            
            query.promise.succeed(result: message)
            messageCache[header.id] = nil
        } catch {
            messageCache[header.id]?.promise.fail(error: error)
            messageCache[header.id] = nil
            ctx.fireErrorCaught(error)
        }
    }
    
    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        for query in self.messageCache.values {
            query.promise.fail(error: error)
        }
        
        messageCache = [:]
    }
}
