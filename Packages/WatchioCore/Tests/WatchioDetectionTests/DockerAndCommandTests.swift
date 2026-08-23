import Foundation
import XCTest

@testable import WatchioDetection
@testable import WatchioModels

final class DockerAndCommandTests: XCTestCase {
  func testDockerComposeInspectionIsCachedAndPathsAreRedacted() async throws {
    let runner = DockerCommandFixture()
    let provider = DockerInventoryProvider(
      runner: runner,
      executable: URL(fileURLWithPath: "/usr/bin/true"),
      homePath: "/Users/demo"
    )

    let first = try await provider.containers()
    let second = try await provider.containers()

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.count, 1)
    XCTAssertEqual(first[0].name, "db")
    XCTAssertEqual(first[0].projectName, "watchio")
    XCTAssertEqual(first[0].projectPath, "~/Code/watchio")
    XCTAssertEqual(first[0].ports.map(\.port), [5432])
    let inspectCalls = await runner.inspectCalls
    XCTAssertEqual(inspectCalls, 1)
  }

  func testCommandRunnerEnforcesTimeout() async throws {
    let runner = ProcessCommandRunner()
    do {
      _ = try await runner.run(
        executable: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["2"],
        timeout: .milliseconds(20)
      )
      XCTFail("Expected the command to time out")
    } catch InventoryError.commandTimedOut {
      // Expected.
    }
  }

  func testDockerRefusesRemoteContextBeforeListingContainers() async throws {
    let runner = DockerCommandFixture(contextEndpoint: "tcp://example.invalid:2376")
    let provider = DockerInventoryProvider(
      runner: runner,
      executable: URL(fileURLWithPath: "/usr/bin/true"),
      homePath: "/Users/demo"
    )

    do {
      _ = try await provider.containers()
      XCTFail("Expected a remote context to be refused")
    } catch InventoryError.unavailable {
      let psCalls = await runner.psCalls
      XCTAssertEqual(psCalls, 0)
    }
  }
}

private actor DockerCommandFixture: CommandRunning {
  private(set) var inspectCalls = 0
  private(set) var psCalls = 0
  private let contextEndpoint: String

  init(contextEndpoint: String = "unix:///Users/demo/.docker/run/docker.sock") {
    self.contextEndpoint = contextEndpoint
  }

  func run(executable: URL, arguments: [String], timeout: Duration) async throws -> CommandResult {
    if arguments.starts(with: ["context", "inspect"]) {
      return CommandResult(
        standardOutput: try JSONEncoder().encode(contextEndpoint),
        standardError: Data(), exitCode: 0)
    }
    if arguments.first == "ps" {
      psCalls += 1
      return CommandResult(
        standardOutput: Data("container-1\n".utf8), standardError: Data(), exitCode: 0)
    }
    if arguments.first == "inspect" {
      inspectCalls += 1
      let json = #"""
        [{
          "Id":"container-1",
          "Name":"/watchio-db-1",
          "Config":{"Labels":{
            "com.docker.compose.project":"watchio",
            "com.docker.compose.service":"db",
            "com.docker.compose.project.working_dir":"/Users/demo/Code/watchio"
          }},
          "State":{"StartedAt":"2026-08-23T10:00:00.123456Z"},
          "NetworkSettings":{"Ports":{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"5432"}]}}
        }]
        """#
      return CommandResult(standardOutput: Data(json.utf8), standardError: Data(), exitCode: 0)
    }
    return CommandResult(standardOutput: Data(), standardError: Data(), exitCode: 1)
  }
}
