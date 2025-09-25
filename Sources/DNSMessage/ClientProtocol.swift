public import NIOCore

public protocol DNSClientProtocol: AnyObject, Sendable {
    // DNSQuery
    func query<RData: DNSResourceData>(
        _ query: DNSQuery<RData>,
        recursionDesired: Bool,
        timeout: TimeAmount
    ) async throws -> DNSQueryResult<RData>

    func query<each RData: DNSResourceData>(
        _ queries: repeat DNSQuery<each RData>,
        recursionDesired: Bool,
        timeout: TimeAmount
    ) async throws -> (repeat DNSQueryResult<each RData>)

    // DNSClientMessage
    func send(_ clientMessage: DNSClientMessage, timeout: TimeAmount) async throws -> DNSMessage

    // DNSQuestion
    func send(
        _ query: any DNSQuestionProtocol,
        recursionDesired: Bool,
        timeout: TimeAmount
    ) async throws -> DNSMessage

    // DNSMessage - Core method that implementations must provide
    func send(_ message: DNSMessage, timeout: TimeAmount) async throws -> DNSMessage
}

extension DNSClientProtocol {
    // DNSQuery
    public func query<RData: DNSResourceData>(
        _ query: DNSQuery<RData>,
        recursionDesired: Bool = true,
        timeout: TimeAmount = .seconds(5)
    ) async throws -> DNSQueryResult<RData> {
        var clientMessage = DNSClientMessage(opcode: .query, recursionDesired: recursionDesired)
        clientMessage.queries.append(query)

        let response = try await self.send(clientMessage, timeout: timeout)
        let requested = response.answers.compactMap({ $0.asResourceRecord(RData.self) })

        return DNSQueryResult(requested: requested, message: response)
    }

    public func query<each RData: DNSResourceData>(
        _ queries: repeat DNSQuery<each RData>,
        recursionDesired: Bool = true,
        timeout: TimeAmount = .seconds(5)
    ) async throws -> (repeat DNSQueryResult<each RData>) {
        async let responses =
            (repeat try self.query(each queries, recursionDesired: recursionDesired, timeout: timeout))
        return try await responses
    }

    // DNSClientMessage
    public func send(
        _ clientMessage: DNSClientMessage,
        timeout: TimeAmount = .seconds(5)
    )
        async throws -> DNSMessage
    {
        try await self.send(try clientMessage.toInternalRepresentation(), timeout: timeout)
    }

    // DNSQuestion
    public func send(
        _ question: any DNSQuestionProtocol,
        recursionDesired: Bool = true,
        timeout: TimeAmount = .seconds(5)
    ) async throws -> DNSMessage {
        var message = createDNSMessage(recursionDesired: recursionDesired)
        message.questions.append(question)
        return try await self.send(message, timeout: timeout)
    }

    // MARK: - Helper Methods

    private func createDNSMessage(recursionDesired: Bool) -> DNSMessage {
        var flags: DNSHeaderFlags = []
        if recursionDesired {
            flags.insert(.recursionDesired)
        }

        // Use DNS ID of 0 for cache friendliness (both DoH and ODoH benefit from this)
        let header = DNSHeader(
            id: 0,
            flags: flags,
            opcode: .query,
            responseCode: .noError
        )

        return DNSMessage(header: header)
    }
}
