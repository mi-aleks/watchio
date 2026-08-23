import Foundation
import XCTest

@testable import WatchioDetection
@testable import WatchioModels

final class ProcessTreeTerminatorIntegrationTests: XCTestCase {
  func testStopsOnlyItsDisposableProcessTreeWithoutSurvivors() async throws {
    guard ProcessInfo.processInfo.environment["WATCHIO_RUN_PROCESS_CONTROL_TESTS"] == "1" else {
      throw XCTSkip(
        "Set WATCHIO_RUN_PROCESS_CONTROL_TESTS=1 to run the disposable process-control test.")
    }

    let fixture = Process()
    fixture.executableURL = URL(fileURLWithPath: "/bin/sh")
    fixture.arguments = ["-c", "/bin/sleep 60 & /bin/sleep 60 & wait"]
    try fixture.run()
    defer {
      if fixture.isRunning {
        fixture.terminate()
        fixture.waitUntilExit()
      }
    }

    let provider = PSProcessInventoryProvider()
    let rootPID = fixture.processIdentifier
    var root: ProcessRecord?
    var originalTree: Set<Int32> = []
    let discoveryDeadline = Date().addingTimeInterval(5)
    while Date() < discoveryDeadline {
      let processes = try await provider.processes()
      if let candidate = processes.first(where: { $0.pid == rootPID }) {
        let descendants = descendantIDs(rootPID: rootPID, processes: processes)
        if descendants.count >= 2 {
          root = candidate
          originalTree = descendants.union([rootPID])
          break
        }
      }
      try await Task.sleep(for: .milliseconds(100))
    }

    let verifiedRoot = try XCTUnwrap(root, "Expected the disposable child tree to start")
    let selectedAt = Date()
    let terminator = ProcessTreeTerminator(processProvider: provider)
    let result = try await terminator.terminate(
      ProcessTerminationTarget(
        representativePID: rootPID,
        representativeStartedAt: selectedAt.addingTimeInterval(-verifiedRoot.elapsedSeconds)))

    let exitDeadline = Date().addingTimeInterval(2)
    while fixture.isRunning, Date() < exitDeadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertFalse(fixture.isRunning, "Expected the disposable root process to exit")
    XCTAssertGreaterThanOrEqual(result.trackedProcessCount, 3)
    XCTAssertEqual(result.survivingProcessCount, 0)

    let remaining = try await provider.processes()
    XCTAssertTrue(
      originalTree.isDisjoint(with: Set(remaining.map(\.pid))),
      "Expected every PID from the disposable tree to be gone")
  }

  private func descendantIDs(rootPID: Int32, processes: [ProcessRecord]) -> Set<Int32> {
    let processByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
    return Set(
      processes.compactMap { process in
        var parentPID = process.parentPID
        var visited: Set<Int32> = [process.pid]
        for _ in 0..<64 {
          guard visited.insert(parentPID).inserted else { return nil }
          if parentPID == rootPID { return process.pid }
          guard let parent = processByPID[parentPID] else { return nil }
          parentPID = parent.parentPID
        }
        return nil
      })
  }
}
