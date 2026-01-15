import NIO
import DNSProtocol

/// Channel handler for UDP DNS server.
final class DNSServerUDPHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>

    private let delegate: DNSServerDelegate
    private let configuration: DNSServerConfiguration

    init(delegate: DNSServerDelegate, configuration: DNSServerConfiguration) {
        self.delegate = delegate
        self.configuration = configuration
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)
        let channel = context.channel

        // Parse the incoming message
        let query: Message
        do {
            query = try DNSMessageDecoder.parse(envelope.data)
        } catch {
            // Invalid message, silently drop (per DNS spec)
            return
        }

        // Only handle queries, not responses
        guard query.header.options.isQuestion else {
            return
        }

        let requestContext = DNSRequestContext(
            remoteAddress: envelope.remoteAddress,
            transport: .udp
        )

        // Capture everything we need before the async task
        let delegate = self.delegate
        let configuration = self.configuration
        let remoteAddress = envelope.remoteAddress
        let allocator = channel.allocator

        // Handle asynchronously using Task and hop back to event loop for writes
        let eventLoop = channel.eventLoop

        Task { [weak channel] in
            do {
                let response = try await delegate.handleQuery(query, context: requestContext)

                // Hop back to event loop for all channel operations
                eventLoop.execute { [weak channel] in
                    guard let channel = channel else { return }

                    var labelIndices = [String: UInt16]()
                    guard let responseBuffer = try? DNSMessageEncoder.encodeMessage(
                        response,
                        allocator: allocator,
                        labelIndices: &labelIndices
                    ) else { return }

                    // Truncate if necessary for UDP
                    let finalBuffer: ByteBuffer
                    if responseBuffer.readableBytes > configuration.maxUDPResponseSize {
                        // Set truncation flag and send partial response
                        let truncatedHeader = DNSMessageHeader(
                            id: response.header.id,
                            options: response.header.options.union(.truncated),
                            questionCount: response.header.questionCount,
                            answerCount: 0,
                            authorityCount: 0,
                            additionalRecordCount: 0
                        )
                        let truncatedResponse = Message(
                            header: truncatedHeader,
                            questions: response.questions,
                            answers: [],
                            authorities: [],
                            additionalData: []
                        )
                        var indices = [String: UInt16]()
                        guard let truncatedBuffer = try? DNSMessageEncoder.encodeMessage(
                            truncatedResponse,
                            allocator: allocator,
                            labelIndices: &indices
                        ) else { return }
                        finalBuffer = truncatedBuffer
                    } else {
                        finalBuffer = responseBuffer
                    }

                    let responseEnvelope = AddressedEnvelope(
                        remoteAddress: remoteAddress,
                        data: finalBuffer
                    )
                    channel.writeAndFlush(responseEnvelope, promise: nil)
                }
            } catch {
                // Send SERVFAIL on error
                eventLoop.execute { [weak channel] in
                    guard let channel = channel else { return }
                    let errorResponse = createErrorResponse(for: query, errorCode: .resultCodeServerfailure)
                    var labelIndices = [String: UInt16]()
                    if let buffer = try? DNSMessageEncoder.encodeMessage(errorResponse, allocator: allocator, labelIndices: &labelIndices) {
                        let errorEnvelope = AddressedEnvelope(remoteAddress: remoteAddress, data: buffer)
                        channel.writeAndFlush(errorEnvelope, promise: nil)
                    }
                }
            }
        }
    }
}

private func createErrorResponse(for query: Message, errorCode: MessageOptions) -> Message {
    Message(
        header: DNSMessageHeader(
            id: query.header.id,
            options: [.answer, errorCode],
            questionCount: UInt16(query.questions.count),
            answerCount: 0,
            authorityCount: 0,
            additionalRecordCount: 0
        ),
        questions: query.questions,
        answers: [],
        authorities: [],
        additionalData: []
    )
}
