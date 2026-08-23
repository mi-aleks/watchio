import Foundation
import XCTest

@testable import WatchioDetection
@testable import WatchioModels

final class RealListenerIntegrationTests: XCTestCase {
  func testDetectsAndRemovesTemporaryNativeListenerWithinFifteenSeconds() async throws {
    guard ProcessInfo.processInfo.environment["WATCHIO_RUN_INTEGRATION_TESTS"] == "1" else {
      throw XCTSkip("Set WATCHIO_RUN_INTEGRATION_TESTS=1 to run the real ps/lsof integration test.")
    }

    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let port = Int.random(in: 49_152...60_000)
    let listener = Process()
    listener.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    listener.arguments = ["-l", "127.0.0.1", String(port)]
    listener.currentDirectoryURL = packageRoot
    try listener.run()
    defer { if listener.isRunning { listener.terminate() } }

    let preferences = DetectionPreferences(projectRoots: [packageRoot.path])
    let engine = DetectionEngine(containerProvider: EmptyContainerProvider())
    var detected = false
    let detectionDeadline = Date().addingTimeInterval(15)
    while Date() < detectionDeadline, !detected {
      try await Task.sleep(for: .seconds(1))
      let result = await engine.scan(preferences: preferences)
      detected = result.services.contains { $0.ports.contains { $0.port == port } }
    }
    XCTAssertTrue(detected, "Expected the native listener to be detected within 15 seconds")

    listener.terminate()
    listener.waitUntilExit()
    var removed = false
    let removalDeadline = Date().addingTimeInterval(15)
    while Date() < removalDeadline, !removed {
      let result = await engine.scan(preferences: preferences)
      removed = !result.services.contains { $0.ports.contains { $0.port == port } }
      if !removed { try await Task.sleep(for: .seconds(1)) }
    }
    XCTAssertTrue(removed, "Expected the listener to disappear within 15 seconds")
  }
}

private struct EmptyContainerProvider: ContainerInventoryProviding {
  func containers() async throws -> [ContainerRecord] { [] }
}
