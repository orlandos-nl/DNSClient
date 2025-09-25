import DNSClient
import DNSMessage
import NIO
import XCTest

#if canImport(Network)
import NIOTransportServices
#endif

final class DNSUDPClientTests: XCTestCase {
    var group: MultiThreadedEventLoopGroup!
    var dnsClient: DNSClient!

    #if canImport(Network)
    var nwGroup: NIOTSEventLoopGroup!
    var nwDnsClient: DNSClient!
    #endif

    @available(*, noasync)
    func testClient(_ perform: (DNSClient) throws -> Void) rethrows {
        try perform(dnsClient)
        #if canImport(Network)
        try perform(nwDnsClient)
        #endif
    }

    func testClient(_ perform: (DNSClient) async throws -> Void) async rethrows {
        try await perform(dnsClient)
        #if canImport(Network)
        try await perform(nwDnsClient)
        #endif
    }

    override func setUpWithError() throws {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        dnsClient = try DNSClient.connect(on: group, host: "8.8.8.8").wait()
        #if canImport(Network)
        nwGroup = NIOTSEventLoopGroup(loopCount: 1)
        nwDnsClient = try DNSClient.connectTS(on: nwGroup, host: "8.8.8.8").wait()
        #endif
    }

    func testAQuery() throws {
        try testClient { dnsClient in
            let results = try dnsClient.initiateAQuery(host: "google.com", port: 443).wait()
            XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
        }
    }

    func testAAAAQuery() throws {
        try testClient { dnsClient in
            let results = try dnsClient.initiateAAAAQuery(host: "google.com", port: 443).wait()
            XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
        }
    }

    func testSendTxtQuery() throws {
        try testClient { dnsClient in
            let result = try dnsClient.sendQuery(forHost: "google.com", type: .txt).wait()
            XCTAssertEqual(result.answers.count, 0, "The returned answers should be 0 on UDP")
        }
    }

    func testSendQueryMX() throws {
        try testClient { dnsClient in
            let result = try dnsClient.sendQuery(forHost: "gmail.com", type: .mx).wait()
            XCTAssertGreaterThanOrEqual(
                result.answers.count,
                1,
                "The returned answers should be greater than or equal to 1"
            )
        }
    }

    func testSendQueryCNAME() throws {
        try testClient { dnsClient in
            let result = try dnsClient.sendQuery(forHost: "www.youtube.com", type: .cname).wait()
            XCTAssertGreaterThanOrEqual(
                result.answers.count,
                1,
                "The returned answers should be greater than or equal to 1"
            )
        }
    }

    func testSRVRecords() throws {
        try testClient { dnsClient in
            let answers = try dnsClient.getSRVRecords(from: "_caldavs._tcp.google.com").wait()
            XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
        }
    }

    func testNSQuery() throws {
        try testClient { dnsClient in
            let results = try dnsClient.initiateNSQuery(forDomain: "example.com").wait()
            XCTAssertEqual(results.count, 2)
            let names = results.map { $0.rData.nsdname.description }.sorted()
            XCTAssertEqual(names, ["a.iana-servers.net", "b.iana-servers.net"])
        }
    }

    func testSOAQuery() throws {
        try testClient { dnsClient in
            let results = try dnsClient.initiateSOAQuery(forDomain: "example.com").wait()
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.rData.mname.description, "ns.icann.org")
        }
    }

    // 4.4.8.8.in-addr.arpa domain points to dns.google.
    func testipv4InverseAddress() throws {
        let answers = try dnsClient.ipv4InverseAddress("8.8.4.4").wait()
        // print("getIPv4PTRRecords: ", answers[0].resource.domainName.string)

        XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
    }

    //  'nslookup 208.67.222.222' has multiple (3) PTR records for opendns.com
    func testipv4InverseAddressMultipleResponses() throws {
        let answers = try dnsClient.ipv4InverseAddress("208.67.222.222").wait()

        // for answer in answers {
        //  print("testPTRRecords2", answer.domainName.string)
        //  print("testPTRRecords2", answer.resource.domainName.string)
        // }

        XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
    }

    func testipv6InverseAddress() throws {
        // dns.google.
        // let answers = try dnsClient.ipv6InverseAddress("2001:4860:4860::8844").wait()

        // j.root-servers.net operated by Verisign, Inc.
        let answers = try dnsClient.ipv6InverseAddress("2001:503:c27::2:30").wait()
        // print("getIPv6PTRRecords: ", answers[0].resource.domainName.string)

        XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
    }

    func testipv6InverseAddressInvalidInput() throws {
        XCTAssertThrowsError(try dnsClient.ipv6InverseAddress(":::0").wait()) { error in

            #if os(Linux)
            XCTAssertEqual(
                error.localizedDescription,
                "The operation could not be completed. (NIOCore.IOError error 1.)"
            )
            #else
            XCTAssertEqual(
                error.localizedDescription,
                "The operation couldn’t be completed. (NIOCore.IOError error 1.)"
            )
            #endif
        }
    }
}
