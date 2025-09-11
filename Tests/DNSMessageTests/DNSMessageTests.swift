import DNSMessage
import NIOCore
import XCTest

final class DNSMessageTests: XCTestCase {
    func testDNSMessageRoundTrip() throws {
        let header = DNSHeader(
            id: 12345,
            flags: [.response, .authoritativeAnswer, .recursionDesired],
            opcode: .query,
            responseCode: .noError
        )

        let question = try DNSQuestion(
            name: DNSName(from: "example.com"),
            type: .a,
            questionClass: .internet
        )

        let aRecord = try ARecord(address: "192.0.2.1")
        let record = try DNSRecord(
            name: DNSName(from: "example.com"),
            rrType: .a,
            dnsClass: .internet,
            ttl: 3600,
            rData: aRecord
        )

        let originalMessage = DNSMessage(
            header: header,
            questions: [question],
            answers: [record]
        )

        var encoder = DNSEncoder()
        _ = try encoder.writeDNSMessage(originalMessage)
        let buffer = encoder.flush()

        var decoder = DNSDecoder(buffer: buffer)
        let decodedMessage = try decoder.readDNSMessage()

        XCTAssertTrue(decodedMessage.isEqual(originalMessage))
    }

    func testARecordRoundTrip() throws {
        let originalRecord = try ARecord(address: "203.0.113.42")

        var encoder = DNSEncoder()
        let bytesWritten = try originalRecord.write(encoder: &encoder)
        XCTAssertEqual(bytesWritten, 4)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try ARecord(from: &decoder, length: 4)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testAAAARecordRoundTrip() throws {
        let originalRecord = try AAAARecord(address: "2001:db8:85a3::8a2e:370:7334")

        var encoder = DNSEncoder()
        let bytesWritten = try originalRecord.write(encoder: &encoder)
        XCTAssertEqual(bytesWritten, 16)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try AAAARecord(from: &decoder, length: 16)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testCNAMERecordRoundTrip() throws {
        let originalRecord = CNAMERecord(cname: try DNSName(from: "alias.example.com"))

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try CNAMERecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testMXRecordRoundTrip() throws {
        let originalRecord = MXRecord(
            preference: 10,
            exchange: try DNSName(from: "mail.example.com")
        )

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try MXRecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testNSRecordRoundTrip() throws {
        let originalRecord = NSRecord(nsdname: try DNSName(from: "ns1.example.com"))

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try NSRecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testPTRRecordRoundTrip() throws {
        let originalRecord = PTRRecord(ptrdname: try DNSName(from: "example.com"))

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try PTRRecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testSOARecordRoundTrip() throws {
        let originalRecord = SOARecord(
            mname: try DNSName(from: "ns1.example.com"),
            rname: try DNSName(from: "admin.example.com"),
            serialNumber: 2_024_010_101,
            refreshInterval: 7200,
            retryInterval: 3600,
            expireInterval: 604800,
            minimumTTL: 86400
        )

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try SOARecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testSRVRecordRoundTrip() throws {
        let originalRecord = SRVRecord(
            priority: 10,
            weight: 5,
            port: 443,
            target: try DNSName(from: "target.example.com")
        )

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try SRVRecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testTXTRecordRoundTrip() throws {
        let originalRecord = try TXTRecord(txtStrings: [
            "v=spf1",
            "include:_spf.example.com",
            "redirect=_spf.example.org",
            "~all",
        ])

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try TXTRecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testHINFORecordRoundTrip() throws {
        let originalRecord = try HINFORecord(cpu: "x86_64", os: "Linux")

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try HINFORecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testNULLRecordRoundTrip() throws {
        let testData: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0xFF, 0xFE, 0xFD, 0xFC]
        let originalRecord = try NULLRecord(data: testData)

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try NULLRecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testHTTPSRecordRoundTrip() throws {
        // Create an HTTPS record with ALPN and port parameters
        let alpnParam = SVCParam(key: .alpn, value: try SVCALPN(alpnStrings: ["h2", "http/1.1"]))
        let portParam = SVCParam(key: .port, value: SVCPort(port: 443))

        let originalRecord = HTTPSRecord(
            svcPriority: 1,
            targetName: try DNSName(from: "https.example.com"),
            svcParams: [alpnParam, portParam]
        )

        var encoder = DNSEncoder()
        _ = try originalRecord.write(encoder: &encoder)

        let buffer = encoder.flush()
        var decoder = DNSDecoder(buffer: buffer)
        let decodedRecord = try HTTPSRecord(from: &decoder, length: buffer.readableBytes)

        XCTAssertEqual(decodedRecord, originalRecord)
    }

    func testComplexDNSMessageRoundTrip() throws {
        let header = DNSHeader(
            id: 54321,
            flags: [.response, .authoritativeAnswer, .recursionAvailable],
            opcode: .query,
            responseCode: .noError
        )

        let question = try DNSQuestion(
            name: DNSName(from: "test.example.com"),
            type: .any,
            questionClass: .internet
        )

        let aRecord = try ARecord(address: "198.51.100.1")
        let aaaaRecord = try AAAARecord(address: "2001:db8::1")
        let cnameRecord = CNAMERecord(cname: try DNSName(from: "canonical.example.com"))
        let mxRecord = MXRecord(preference: 20, exchange: try DNSName(from: "mail.example.com"))

        let records = [
            try DNSRecord(
                name: DNSName(from: "test.example.com"),
                rrType: .a,
                dnsClass: .internet,
                ttl: 300,
                rData: aRecord
            ),
            try DNSRecord(
                name: DNSName(from: "test.example.com"),
                rrType: .aaaa,
                dnsClass: .internet,
                ttl: 300,
                rData: aaaaRecord
            ),
            try DNSRecord(
                name: DNSName(from: "alias.example.com"),
                rrType: .cname,
                dnsClass: .internet,
                ttl: 600,
                rData: cnameRecord
            ),
            try DNSRecord(
                name: DNSName(from: "example.com"),
                rrType: .mx,
                dnsClass: .internet,
                ttl: 3600,
                rData: mxRecord
            ),
        ]

        let originalMessage = DNSMessage(
            header: header,
            questions: [question],
            answers: records
        )

        var encoder = DNSEncoder()
        _ = try encoder.writeDNSMessage(originalMessage)
        let buffer = encoder.flush()

        var decoder = DNSDecoder(buffer: buffer)
        let decodedMessage = try decoder.readDNSMessage()

        XCTAssertTrue(decodedMessage.isEqual(originalMessage))
    }

    func testDNSNameCompression() throws {
        let message = DNSMessage(
            header: DNSHeader(id: 1, flags: [], opcode: .query, responseCode: .noError),
            questions: [
                try DNSQuestion(name: DNSName(from: "sub1.example.com"), type: .a, questionClass: .internet),
                try DNSQuestion(name: DNSName(from: "sub2.example.com"), type: .a, questionClass: .internet),
            ]
        )

        var compressedEncoder = DNSEncoder(nameEncoding: .compressed)
        let compressedSize = try compressedEncoder.writeDNSMessage(message)

        var uncompressedEncoder = DNSEncoder(nameEncoding: .uncompressed)
        let uncompressedSize = try uncompressedEncoder.writeDNSMessage(message)

        XCTAssertLessThan(compressedSize, uncompressedSize, "Compression should reduce message size")

        let compressedBuffer = compressedEncoder.flush()
        var decoder1 = DNSDecoder(buffer: compressedBuffer)
        let decodedCompressed = try decoder1.readDNSMessage()

        let uncompressedBuffer = uncompressedEncoder.flush()
        var decoder2 = DNSDecoder(buffer: uncompressedBuffer)
        let decodedUncompressed = try decoder2.readDNSMessage()

        XCTAssertTrue(decodedCompressed.isEqual(decodedUncompressed))
        XCTAssertTrue(decodedCompressed.isEqual(message))
    }

    func testMultipleRecordTypesMessage() throws {
        let header = DNSHeader(
            id: 9999,
            flags: [.response, .recursionAvailable],
            opcode: .query,
            responseCode: .noError
        )

        let question = try DNSQuestion(
            name: DNSName(from: "multi.example.com"),
            type: .any,
            questionClass: .internet
        )

        let answers = [
            try DNSRecord(
                name: DNSName(from: "multi.example.com"),
                rrType: .a,
                dnsClass: .internet,
                ttl: 300,
                rData: try ARecord(address: "192.0.2.100")
            ),
            try DNSRecord(
                name: DNSName(from: "multi.example.com"),
                rrType: .aaaa,
                dnsClass: .internet,
                ttl: 300,
                rData: try AAAARecord(address: "2001:db8::100")
            ),
            try DNSRecord(
                name: DNSName(from: "multi.example.com"),
                rrType: .txt,
                dnsClass: .internet,
                ttl: 600,
                rData: try TXTRecord(txtStrings: ["version=1.0", "contact=admin@example.com"])
            ),
        ]

        let authorities = [
            try DNSRecord(
                name: DNSName(from: "example.com"),
                rrType: .ns,
                dnsClass: .internet,
                ttl: 86400,
                rData: NSRecord(nsdname: try DNSName(from: "ns1.example.com"))
            ),
            try DNSRecord(
                name: DNSName(from: "example.com"),
                rrType: .ns,
                dnsClass: .internet,
                ttl: 86400,
                rData: NSRecord(nsdname: try DNSName(from: "ns2.example.com"))
            ),
        ]

        let originalMessage = DNSMessage(
            header: header,
            questions: [question],
            answers: answers,
            authorities: authorities
        )

        var encoder = DNSEncoder()
        _ = try encoder.writeDNSMessage(originalMessage)
        let buffer = encoder.flush()

        var decoder = DNSDecoder(buffer: buffer)
        let decodedMessage = try decoder.readDNSMessage()

        XCTAssertTrue(decodedMessage.isEqual(originalMessage))
    }

    func testEmptyMessage() throws {
        let originalMessage = DNSMessage(
            header: DNSHeader(id: 0, flags: [], opcode: .query, responseCode: .noError)
        )

        var encoder = DNSEncoder()
        _ = try encoder.writeDNSMessage(originalMessage)
        let buffer = encoder.flush()

        var decoder = DNSDecoder(buffer: buffer)
        let decodedMessage = try decoder.readDNSMessage()

        XCTAssertTrue(decodedMessage.isEqual(originalMessage))
    }
}
