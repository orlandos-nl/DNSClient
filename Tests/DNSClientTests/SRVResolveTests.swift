import XCTest
import NIO
import NIOEmbedded

#if canImport(Network)
import NIOTransportServices
#endif
@testable import DNSClient

final class SRVResolveTests: XCTestCase {
    private enum TestFailure: Error {
        case missingOutbound
        case missingQuestion
    }
    private final class EmbeddedEventLoopGroup: EventLoopGroup {
        let loop: EmbeddedEventLoop

        init(loop: EmbeddedEventLoop) {
            self.loop = loop
        }

        func next() -> EventLoop { loop }
        func any() -> EventLoop { loop }
        func makeIterator() -> EventLoopIterator { EventLoopIterator([loop]) }
        func _preconditionSafeToSyncShutdown(file: StaticString, line: UInt) {}

        func shutdownGracefully(queue: DispatchQueue, _ callback: @Sendable @escaping (Error?) -> Void) {
            callback(nil)
        }
    }
    private func labels(_ parts: [String]) -> [DNSLabel] {
        parts.map { DNSLabel(stringLiteral: $0) }
    }

    private func makeSRV(owner: [DNSLabel], target: [DNSLabel], priority: UInt16, weight: UInt16, port: UInt16) -> Record {
        let srv = SRVRecord(priority: priority, weight: weight, port: port, domainName: target)
        let rr = ResourceRecord(domainName: owner, dataType: DNSResourceType.srv.rawValue, dataClass: DataClass.internet.rawValue, ttl: 60, resource: srv)
        return .srv(rr)
    }

    private func makeA(owner: [DNSLabel], address: UInt32) -> Record {
        let rr = ResourceRecord(domainName: owner, dataType: DNSResourceType.a.rawValue, dataClass: DataClass.internet.rawValue, ttl: 60, resource: ARecord(address: address))
        return .a(rr)
    }

    private func makeAAAA(owner: [DNSLabel], address: [UInt8]) -> Record {
        let rr = ResourceRecord(domainName: owner, dataType: DNSResourceType.aaaa.rawValue, dataClass: DataClass.internet.rawValue, ttl: 60, resource: AAAARecord(address: address))
        return .aaaa(rr)
    }

    private func makeResponse(
        id: UInt16,
        answers: [Record],
        additional: [Record] = []
    ) -> Message {
        let header = DNSMessageHeader(
            id: id,
            options: [.answer],
            questionCount: 0,
            answerCount: UInt16(answers.count),
            authorityCount: 0,
            additionalRecordCount: UInt16(additional.count)
        )
        return Message(header: header, questions: [], answers: answers, authorities: [], additionalData: additional)
    }

    private func encodeResponse(_ message: Message, allocator: ByteBufferAllocator) throws -> ByteBuffer {
        var out = allocator.buffer(capacity: 512)
        out.write(message.header)
        // No questions in synthetic responses for these tests.
        for answer in message.answers {
            try out.writeAnyRecordUncompressed(answer)
        }
        for additional in message.additionalData {
            try out.writeAnyRecordUncompressed(additional)
        }
        return out
    }

    private func readOutboundQuery(_ channel: EmbeddedChannel) throws -> (UInt16, String, DNSResourceType) {
        guard let buffer: ByteBuffer = try channel.readOutbound() else {
            XCTFail("Expected outbound query")
            throw TestFailure.missingOutbound
        }
        let message = try DNSMessageDecoder.parse(buffer)
        guard let question = message.questions.first else {
            XCTFail("Expected question in outbound message")
            throw TestFailure.missingQuestion
        }
        return (message.header.id, question.labels.string, question.type)
    }

    private func drainOutboundQueries(_ channel: EmbeddedChannel) throws -> [(UInt16, String, DNSResourceType)] {
        var queries: [(UInt16, String, DNSResourceType)] = []
        while let buffer: ByteBuffer = try channel.readOutbound() {
            let message = try DNSMessageDecoder.parse(buffer)
            if let question = message.questions.first {
                queries.append((message.header.id, question.labels.string, question.type))
            }
        }
        return queries
    }

    func testResolveSRVUsesAdditionalAndLooksUpMissing() throws {
        let loop = EmbeddedEventLoop()
        let group = EmbeddedEventLoopGroup(loop: loop)
        let channel = EmbeddedChannel(loop: loop)
        let decoder = DNSDecoder(group: group)
        try channel.pipeline.syncOperations.addHandlers(decoder, DNSEncoder())

        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 53)
        let client = DNSClient(channel: channel, address: address, decoder: decoder)

        let host = "_svc._tcp.owner.tld0"
        let owner = labels(["_svc", "_tcp", "owner", "tld0", ""])
        let targetA = labels(["a", "alpha", "tld1", ""])
        let targetB = labels(["b", "beta", "tld2", ""])

        let future = client.resolveSRV(from: host)
        loop.run()

        // SRV query
        let (srvID, srvName, srvType) = try readOutboundQuery(channel)
        XCTAssertEqual(srvType, .srv)
        XCTAssertEqual(srvName, host)

        let srvAnswers: [Record] = [
            makeSRV(owner: owner, target: targetA, priority: 0, weight: 0, port: 443),
            makeSRV(owner: owner, target: targetB, priority: 10, weight: 0, port: 443)
        ]
        let additional: [Record] = [
            makeA(owner: targetA, address: 0xC0000201) // 192.0.2.1
        ]

        let srvResponse = makeResponse(id: srvID, answers: srvAnswers, additional: additional)
        try channel.writeInbound(encodeResponse(srvResponse, allocator: channel.allocator))
        loop.run()

        let queries = try drainOutboundQueries(channel)
        XCTAssertEqual(queries.count, 2)
        XCTAssertEqual(Set(queries.map { $0.2 }), [.a, .aaaa])
        XCTAssertEqual(Set(queries.map { $0.1 }), ["b.beta.tld2"])

        for (id, name, type) in queries {
            XCTAssertEqual(name, "b.beta.tld2")
            let response: Message
            switch type {
            case .a:
                response = makeResponse(id: id, answers: [makeA(owner: targetB, address: 0x0A000001)]) // 10.0.0.1
            case .aaaa:
                response = makeResponse(id: id, answers: [makeAAAA(owner: targetB, address: [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])])
            default:
                XCTFail("Unexpected query type \(type)")
                continue
            }
            try channel.writeInbound(encodeResponse(response, allocator: channel.allocator))
        }
        loop.run()

        let resolved = try future.wait()
        XCTAssertEqual(resolved.count, 2)

        let first = resolved[0]
        XCTAssertEqual(first.record.resource.domainName.string, "a.alpha.tld1")
        XCTAssertTrue(first.fromAdditional)
        XCTAssertEqual(first.addresses.first?.ipAddress, "192.0.2.1")
        XCTAssertEqual(first.addresses.first?.port, 443)

        let second = resolved[1]
        XCTAssertEqual(second.record.resource.domainName.string, "b.beta.tld2")
        XCTAssertFalse(second.fromAdditional)
        let ips = Set(second.addresses.compactMap { $0.ipAddress })
        XCTAssertEqual(ips, ["10.0.0.1", "2001:db8::1"])
        XCTAssertTrue(second.addresses.allSatisfy { $0.port == 443 })
    }

    func testResolveSRVSingleDotTargetFails() throws {
        let loop = EmbeddedEventLoop()
        let group = EmbeddedEventLoopGroup(loop: loop)
        let channel = EmbeddedChannel(loop: loop)
        let decoder = DNSDecoder(group: group)
        try channel.pipeline.syncOperations.addHandlers(decoder, DNSEncoder())

        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 53)
        let client = DNSClient(channel: channel, address: address, decoder: decoder)

        let host = "_svc._tcp.example.com"
        let owner = labels(["_svc", "_tcp", "example", "com", ""])
        let rootTarget = labels([""])

        let future = client.resolveSRV(from: host)
        loop.run()

        let (srvID, _, _) = try readOutboundQuery(channel)
        let srvAnswer = makeSRV(owner: owner, target: rootTarget, priority: 0, weight: 0, port: 443)
        let response = makeResponse(id: srvID, answers: [srvAnswer])
        try channel.writeInbound(encodeResponse(response, allocator: channel.allocator))
        loop.run()

        XCTAssertThrowsError(try future.wait()) { error in
            XCTAssertNotNil(error as? SRVServiceUnavailable)
        }
    }
}
