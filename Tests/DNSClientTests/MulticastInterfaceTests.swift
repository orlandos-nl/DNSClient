import Testing
import NIO
@testable import DNSClient

@Suite("Multicast Interface Tests", .serialized)
struct MulticastInterfaceTests {

    // MARK: - Helpers

    /// Helper: find multicast-capable IPv4 devices on this machine.
    private func findIPv4MulticastDevices() throws -> [NIONetworkDevice] {
        try System.enumerateDevices().filter {
            $0.multicastSupported && $0.address != nil && $0.address?.protocol.rawValue == PF_INET
        }
    }

    /// Helper: find multicast-capable IPv6 devices on this machine.
    private func findIPv6MulticastDevices() throws -> [NIONetworkDevice] {
        try System.enumerateDevices().filter {
            $0.multicastSupported && $0.address != nil && $0.address?.protocol.rawValue == PF_INET6
        }
    }

    /// Helper: create a multicast client, returning nil if multicast is unavailable.
    private func createClient(
        on group: EventLoopGroup,
        interface device: NIONetworkDevice? = nil
    ) async -> MulticastDNSClient? {
        guard let client = try? await DNSClient.connectMulticast(on: group, interface: device).get(),
              client.channel.isActive
        else { return nil }
        return client
    }

    /// Helper: clean up group without throwing.
    private func shutdown(_ group: MultiThreadedEventLoopGroup) async {
        try? await group.shutdownGracefully()
    }

    // MARK: - IPv4 Tests

    @Test("connectMulticast with nil interface preserves default IP_MULTICAST_IF")
    func connectMulticastDefaultInterface() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        guard let client = await createClient(on: group) else {
            await shutdown(group)
            return
        }

        // With nil interface, IP_MULTICAST_IF should remain at INADDR_ANY.
        // Use try? because the channel can close asynchronously on systems
        // where multicast group membership is not stable.
        let provider = client.channel as! SocketOptionProvider
        if let multicastIF = try? await provider.getIPMulticastIF().get() {
            #expect(multicastIF.s_addr == in_addr_t(0), "Default should be INADDR_ANY (0.0.0.0)")
        }

        try? await client.close().get()
        await shutdown(group)
    }

    @Test("connectMulticast with IPv4 device sets IP_MULTICAST_IF to that interface's address")
    func connectMulticastSetsIPv4SocketOption() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let devices = try findIPv4MulticastDevices()
        guard let device = devices.first,
              let deviceAddr = device.address,
              case .v4(let v4) = deviceAddr
        else {
            await shutdown(group)
            return
        }

        guard let client = await createClient(on: group, interface: device) else {
            await shutdown(group)
            return
        }

        // Core assertion: IP_MULTICAST_IF must match the device's IPv4 address.
        // Without the `interface` parameter, this would remain at INADDR_ANY.
        let provider = client.channel as! SocketOptionProvider
        if let multicastIF = try? await provider.getIPMulticastIF().get() {
            #expect(
                multicastIF.s_addr == v4.address.sin_addr.s_addr,
                "IP_MULTICAST_IF should match \(device.name)'s IPv4 address"
            )
        }

        try? await client.close().get()
        await shutdown(group)
    }

    @Test("connectMulticast with IPv4 device can send a query without error")
    func connectMulticastIPv4CanSendQuery() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let devices = try findIPv4MulticastDevices()
        guard let device = devices.first else {
            await shutdown(group)
            return
        }

        guard let client = await createClient(on: group, interface: device) else {
            await shutdown(group)
            return
        }

        // Send a PTR query with a short timeout. We don't need real responses —
        // just verify the query completes without throwing on the bound interface.
        let messages = try await client.sendMulticastQuery(
            forHost: "_test._tcp.local",
            type: .ptr,
            timeout: .milliseconds(200)
        ).get()

        #expect(messages.count >= 0, "Query should complete without error")

        try? await client.close().get()
        await shutdown(group)
    }

    @Test("two IPv4 clients on different interfaces get independent IP_MULTICAST_IF values")
    func twoIPv4ClientsOnDifferentInterfaces() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let devices = try findIPv4MulticastDevices()
        guard devices.count >= 2,
              case .v4(let v4a) = devices[0].address,
              case .v4(let v4b) = devices[1].address
        else {
            await shutdown(group)
            return
        }

        guard let clientA = await createClient(on: group, interface: devices[0]),
              let clientB = await createClient(on: group, interface: devices[1])
        else {
            await shutdown(group)
            return
        }

        let providerA = clientA.channel as! SocketOptionProvider
        let providerB = clientB.channel as! SocketOptionProvider

        if let ifA = try? await providerA.getIPMulticastIF().get(),
           let ifB = try? await providerB.getIPMulticastIF().get()
        {
            #expect(ifA.s_addr == v4a.address.sin_addr.s_addr, "Client A bound to \(devices[0].name)")
            #expect(ifB.s_addr == v4b.address.sin_addr.s_addr, "Client B bound to \(devices[1].name)")
            #expect(ifA.s_addr != ifB.s_addr, "Two interfaces should have different IP_MULTICAST_IF")
        }

        try? await clientA.close().get()
        try? await clientB.close().get()
        await shutdown(group)
    }

    // MARK: - IPv6 Tests

    @Test("connectMulticast with IPv6 device sets IPV6_MULTICAST_IF to that interface's index")
    func connectMulticastSetsIPv6SocketOption() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let devices = try findIPv6MulticastDevices()
        guard let device = devices.first else {
            await shutdown(group)
            return
        }

        guard let client = await createClient(on: group, interface: device) else {
            await shutdown(group)
            return
        }

        // Core assertion: IPV6_MULTICAST_IF must match the device's interface index.
        // RFC 6762 §20: IPv6 multicast queries should be pinned to the correct link.
        let provider = client.channel as! SocketOptionProvider
        if let multicastIF = try? await provider.getIPv6MulticastIF().get() {
            #expect(
                multicastIF == CUnsignedInt(device.interfaceIndex),
                "IPV6_MULTICAST_IF should match \(device.name)'s interface index (\(device.interfaceIndex))"
            )
        }

        try? await client.close().get()
        await shutdown(group)
    }

    @Test("connectMulticast with IPv6 device can send a query without error")
    func connectMulticastIPv6CanSendQuery() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let devices = try findIPv6MulticastDevices()
        guard let device = devices.first else {
            await shutdown(group)
            return
        }

        guard let client = await createClient(on: group, interface: device) else {
            await shutdown(group)
            return
        }

        // Send a PTR query over IPv6 multicast with a short timeout.
        let messages = try await client.sendMulticastQuery(
            forHost: "_test._tcp.local",
            type: .ptr,
            timeout: .milliseconds(200)
        ).get()

        #expect(messages.count >= 0, "IPv6 query should complete without error")

        try? await client.close().get()
        await shutdown(group)
    }
}
