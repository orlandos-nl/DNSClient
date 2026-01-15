import NIO
import DNSProtocol

/// Channel handler for TCP DNS server connections.
final class DNSServerTCPHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let delegate: DNSServerDelegate
    private var remoteAddress: SocketAddress?

    init(delegate: DNSServerDelegate) {
        self.delegate = delegate
    }

    func channelActive(context: ChannelHandlerContext) {
        remoteAddress = context.channel.remoteAddress
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let channel = context.channel

        let query: Message
        do {
            query = try DNSMessageDecoder.parse(buffer)
        } catch {
            // Invalid message, close connection
            context.close(promise: nil)
            return
        }

        guard query.header.options.isQuestion else {
            return
        }

        let fallbackAddress = try! SocketAddress(ipAddress: "0.0.0.0", port: 0)
        let requestContext = DNSRequestContext(
            remoteAddress: remoteAddress ?? fallbackAddress,
            transport: .tcp
        )

        // Capture delegate and allocator before async task
        let delegate = self.delegate
        let allocator = channel.allocator
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

                    // TCP doesn't have size limits like UDP
                    channel.writeAndFlush(responseBuffer, promise: nil)
                }
            } catch {
                // Send SERVFAIL on error
                eventLoop.execute { [weak channel] in
                    guard let channel = channel else { return }
                    let errorResponse = createTCPErrorResponse(for: query)
                    var labelIndices = [String: UInt16]()
                    if let buffer = try? DNSMessageEncoder.encodeMessage(errorResponse, allocator: allocator, labelIndices: &labelIndices) {
                        channel.writeAndFlush(buffer, promise: nil)
                    }
                }
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

private func createTCPErrorResponse(for query: Message) -> Message {
    Message(
        header: DNSMessageHeader(
            id: query.header.id,
            options: [.answer, .resultCodeServerfailure],
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
