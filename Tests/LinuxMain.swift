import XCTest
import DNSClientTests

var tests = [XCTestCaseEntry]()
tests += DNSClientTests.allTests()
XCTMain(tests)