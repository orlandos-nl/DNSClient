import XCTest
import NioDNSTests

var tests = [XCTestCaseEntry]()
tests += NioDNSTests.allTests()
XCTMain(tests)