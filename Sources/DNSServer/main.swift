import DNSClient
import NIO

let el = NIOSingletons.posixEventLoopGroup.next()
let server = DatagramBootstrap(group: el)
let _channel = try await server.bind(host: "0.0.0.0", port: 5335).get()
let channel = try await el.submit {
    try NIOAsyncChannel<
        AddressedEnvelope<ByteBuffer>,
        AddressedEnvelope<ByteBuffer>
    >(
        wrappingChannelSynchronously: _channel
    )
}.get()

try await channel.executeThenClose {
    inbound,
    outbound in
    var i: UInt16 = 0
    for try await envelope in inbound {
        do {
            let inbound = try DNSDecoder.parse(envelope.data)
            
            guard let question = inbound.questions.first else {
                continue
            }
            
            let message = Message(
                header: DNSMessageHeader(
                    id: inbound.header.id,
                    options: .answer,
                    questionCount: 0,
                    answerCount: 1,
                    authorityCount: 0,
                    additionalRecordCount: 0
                ),
                questions: [],
                answers: [
                    .a(
                        ResourceRecord<ARecord>(
                            domainName: question.labels,
                            dataType: question.type.rawValue,
                            dataClass: question.questionClass.rawValue,
                            ttl: 100,
                            resource: ARecord(address: 12312312)
                        )
                    )
                ],
                authorities: [],
                additionalData: []
            )

            var labelIndices = [String: UInt16]()
            labelIndices["com"] = i
            i += 1

            try await outbound.write(
                AddressedEnvelope<ByteBuffer>(
                    remoteAddress: envelope.remoteAddress,
                    data: DNSEncoder.encodeMessage(
                        message,
                        allocator: channel.channel.allocator,
                        labelIndices: &labelIndices
                    )
                )
            )
        } catch {}
    }
}
