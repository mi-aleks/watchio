import Foundation
import XCTest

@testable import WatchioDetection
@testable import WatchioModels

final class InventoryParserTests: XCTestCase {
  func testParsesPSOutputWithSpacesAndElapsedVariants() throws {
    let output = """
        501  102  1  102 ttys001  01:02  4.2  1200 /Users/demo/Tools/Node Runtime/node
        501  103  1  103 ??  2-03:04:05  0.0  42 /opt/homebrew/bin/python3.12
      """
    let records = PSInventoryParser.parse(output)
    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(records[0].executablePath, "/Users/demo/Tools/Node Runtime/node")
    XCTAssertEqual(records[0].elapsedSeconds, 62)
    XCTAssertEqual(records[0].memoryBytes, 1_228_800)
    XCTAssertNil(records[1].tty)
    XCTAssertEqual(records[1].elapsedSeconds, 183_845)
  }

  func testParsesElapsedVariants() {
    for (value, expected) in [("00:03", 3.0), ("01:02:03", 3_723.0), ("3-00:00:01", 259_201.0)] {
      XCTAssertEqual(PSInventoryParser.parseElapsed(value), expected)
    }
  }

  func testParsesIPv4IPv6AndMultipleListeners() {
    let output = """
      p100
      cnode
      f21
      n127.0.0.1:3000
      f22
      n[::1]:3001
      p101
      cpython
      f23
      n*:8080
      """
    let records = LsofInventoryParser.parseListeners(output, transport: .tcp)
    XCTAssertEqual(records.count, 3)
    XCTAssertTrue(
      records.contains(
        PortRecord(pid: 100, endpoint: .init(transport: .tcp, address: "::1", port: 3001))))
    XCTAssertTrue(
      records.contains(
        PortRecord(pid: 101, endpoint: .init(transport: .tcp, address: "*", port: 8080))))
  }

  func testParsesWorkingDirectoriesWithSpaces() {
    let output = """
      p100
      fcwd
      n/Users/demo/Code/Project With Spaces
      p101
      fcwd
      n/Users/demo/Code/api
      """
    let paths = LsofInventoryParser.parseWorkingDirectories(output)
    XCTAssertEqual(paths[100], "/Users/demo/Code/Project With Spaces")
    XCTAssertEqual(paths[101], "/Users/demo/Code/api")
  }
}
