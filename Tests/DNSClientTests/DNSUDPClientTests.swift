import XCTest
import NIO
import DNSClient

final class DNSUDPClientTests: XCTestCase {
    var group: MultiThreadedEventLoopGroup!
    var dnsClient: DNSClient!

    override func setUp() {
        super.setUp()
        do {
            group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            dnsClient = try DNSClient.connect(on: group, host: "8.8.8.8").wait()
        } catch let error {
            XCTFail("\(error)")
        }
    }
    
    func testStringAddress() throws {
        var buffer = ByteBuffer()
        buffer.writeInteger(0x7F000001 as UInt32)
        guard let record = ARecord.read(from: &buffer, length: buffer.readableBytes) else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(record.stringAddress, "127.0.0.1")
    }

    func testStringAddressAAAA() throws {
        var buffer = ByteBuffer()
        buffer.writeBytes([0x2a, 0x00, 0x14, 0x50, 0x40, 0x01, 0x08, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x0e] as [UInt8])

        guard let record = AAAARecord.read(from: &buffer, length: buffer.readableBytes) else {
            XCTFail()
            return
        }

        XCTAssertEqual(record.stringAddress, "2a00:1450:4001:0809:0000:0000:0000:200e")
    }

    func testAQuery() throws {
        let results = try dnsClient.initiateAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
    }

    func testAAAAQuery() throws {
        let results = try dnsClient.initiateAAAAQuery(host: "google.com", port: 443).wait()
        XCTAssertGreaterThanOrEqual(results.count, 1, "The returned result should be greater than or equal to 1")
    }

    func testSendTxtQuery() throws {
        let result = try dnsClient.sendQuery(forHost: "google.com", type: .txt).wait()
        XCTAssertEqual(result.header.answerCount, 0, "The returned answers should be 0 on UDP")
    }

    func testSendQueryMX() throws {
        let result = try dnsClient.sendQuery(forHost: "gmail.com", type: .mx).wait()
        XCTAssertGreaterThanOrEqual(result.header.answerCount, 1, "The returned answers should be greater than or equal to 1")
    }

    func testSendQueryCNAME() throws {
        let result = try dnsClient.sendQuery(forHost: "www.youtube.com", type: .cName).wait()
        XCTAssertGreaterThanOrEqual(result.header.answerCount, 1, "The returned answers should be greater than or equal to 1")
    }

    func testSRVRecords() throws {
        let answers = try dnsClient.getSRVRecords(from: "_mongodb._tcp.ok0-xkvc1.mongodb.net").wait()
        XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
    }
    
    func testSRVRecordsAsyncRequest() throws {
        let expectation = self.expectation(description: "getSRVRecords")
        
        dnsClient.getSRVRecords(from: "_mongodb._tcp.ok0-xkvc1.mongodb.net")
            .whenComplete { (result) in
                switch result {
                case .failure(let error):
                    XCTFail("\(error)")
                case .success(let answers):
                    XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
                }
                expectation.fulfill()
            }
        self.waitForExpectations(timeout: 5, handler: nil)
    }
    
    func testSRVRecordsAsyncRequest2() async throws {
        for _ in 0..<50 {
            let answers = try await dnsClient.getSRVRecords(from: "_mongodb._tcp.ok0-xkvc1.mongodb.net").get()
            XCTAssertGreaterThanOrEqual(answers.count, 1, "The returned answers should be greater than or equal to 1")
            for answer in answers {
                let countA = try await dnsClient.initiateAAAAQuery(host: answer.resource.domainName.string, port: 27017).get().count
                let countAAAA = try await dnsClient.initiateAQuery(host: answer.resource.domainName.string, port: 27017).get().count
                
                XCTAssertGreaterThan(countA + countAAAA, 0)
            }
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
        
        XCTAssertEqual(answers.count, 3, "The returned answers should be equal to 3")
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
            XCTAssertEqual(error.localizedDescription , "The operation couldn’t be completed. (NIOCore.IOError error 1.)")
        }
    }
    
    func testPTRRecordDescription() throws {
        let domainname = PTRRecord(domainName: [DNSLabel(stringLiteral: "dns"),
                                               DNSLabel(stringLiteral: "google"),
                                               DNSLabel(stringLiteral: "")])
        
        XCTAssertEqual(domainname.description, "PTRRecord: dns.google")
    }
}
