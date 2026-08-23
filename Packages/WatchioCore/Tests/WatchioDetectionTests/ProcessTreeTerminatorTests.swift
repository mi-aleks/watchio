import Foundation
import XCTest

@testable import WatchioDetection
@testable import WatchioModels

final class ProcessTreeTerminatorTests: XCTestCase {
  private let observedAt = Date(timeIntervalSince1970: 10_000)

  func testGracefullyTerminatesFrozenRootAndDescendants() async throws {
    let root = terminationProcess(pid: 100, ppid: 10, elapsed: 20, path: "/tool/node")
    let child = terminationProcess(pid: 101, ppid: 100, elapsed: 10, path: "/tool/helper")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(
      snapshots: [[root, child], [root, child], [root, child], []], signaler: signaler)

    let result = try await terminator.terminate(target(for: root))

    XCTAssertEqual(result.trackedProcessCount, 2)
    XCTAssertEqual(result.forceKilledProcessCount, 0)
    XCTAssertEqual(result.survivingProcessCount, 0)
    XCTAssertEqual(
      signaler.events,
      [
        .init(signal: .stop, pid: 100), .init(signal: .stop, pid: 101),
        .init(signal: .terminate, pid: 101), .init(signal: .terminate, pid: 100),
        .init(signal: .resume, pid: 101), .init(signal: .resume, pid: 100),
      ])
  }

  func testReusedDescendantPIDFailsBeforeTermAndResumesFrozenTree() async {
    let root = terminationProcess(pid: 150, ppid: 10, elapsed: 30, path: "/tool/node")
    let child = terminationProcess(pid: 151, ppid: 150, elapsed: 10, path: "/tool/helper")
    let reusedChild = terminationProcess(
      pid: 151, ppid: 150, elapsed: 0, path: "/Applications/Other.app/Other")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(
      snapshots: [[root, child], [root, child], [root, reusedChild]], signaler: signaler)

    await assertTerminationError(.identityChanged) {
      try await terminator.terminate(self.target(for: root))
    }

    XCTAssertFalse(signaler.events.contains { $0.signal == .terminate || $0.signal == .kill })
    XCTAssertEqual(
      Set(signaler.events.filter { $0.signal == .resume }.map(\.pid)), Set([150]))
  }

  func testForceKillsOnlyVerifiedSurvivorsAfterGracePeriod() async throws {
    let root = terminationProcess(pid: 200, ppid: 10, elapsed: 30, path: "/tool/claude")
    let child = terminationProcess(pid: 201, ppid: 200, elapsed: 10, path: "/tool/helper")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(
      snapshots: [
        [root, child], [root, child], [root, child], [root, child], [root, child], [],
      ], signaler: signaler, gracePollAttempts: 1)

    let result = try await terminator.terminate(target(for: root))

    XCTAssertEqual(result.trackedProcessCount, 2)
    XCTAssertEqual(result.forceKilledProcessCount, 2)
    XCTAssertEqual(result.survivingProcessCount, 0)
    XCTAssertEqual(
      signaler.events.filter { $0.signal == .kill }.map(\.pid),
      [201, 200])
  }

  func testFreezePassesCaptureAChangingDescendantTree() async throws {
    let root = terminationProcess(pid: 300, ppid: 10, elapsed: 40, path: "/tool/codex")
    let child = terminationProcess(pid: 301, ppid: 300, elapsed: 12, path: "/tool/helper")
    let grandchild = terminationProcess(pid: 302, ppid: 301, elapsed: 4, path: "/tool/worker")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(
      snapshots: [
        [root], [root, child], [root, child, grandchild], [root, child, grandchild], [],
      ], signaler: signaler)

    let result = try await terminator.terminate(target(for: root))

    XCTAssertEqual(result.trackedProcessCount, 3)
    XCTAssertEqual(
      signaler.events.filter { $0.signal == .stop }.map(\.pid),
      [300, 301, 302])
  }

  func testGracePeriodCapturesAndTerminatesNewTailProcesses() async throws {
    let root = terminationProcess(pid: 400, ppid: 10, elapsed: 40, path: "/tool/node")
    let tail = terminationProcess(pid: 401, ppid: 400, elapsed: 1, path: "/tool/tail")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(
      snapshots: [[root], [root], [root, tail], []], signaler: signaler,
      gracePollAttempts: 2)

    let result = try await terminator.terminate(target(for: root))

    XCTAssertEqual(result.trackedProcessCount, 2)
    XCTAssertTrue(signaler.events.contains(.init(signal: .terminate, pid: 401)))
  }

  func testPIDReuseFailsClosedWithoutSignalingTheReusedPID() async {
    let root = terminationProcess(pid: 500, ppid: 10, elapsed: 20, path: "/tool/node")
    let reused = terminationProcess(pid: 500, ppid: 10, elapsed: 0, path: "/tool/python")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(snapshots: [[root], [reused]], signaler: signaler)

    await assertTerminationError(.identityChanged) {
      try await terminator.terminate(self.target(for: root))
    }
    XCTAssertEqual(
      signaler.events,
      [.init(signal: .stop, pid: 500)])
  }

  func testExecutableChangeOnSameKernelProcessOnlyReceivesCleanupResume() async {
    let root = terminationProcess(pid: 550, ppid: 10, elapsed: 20, path: "/tool/node")
    let executed = terminationProcess(pid: 550, ppid: 10, elapsed: 20, path: "/tool/python")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(snapshots: [[root], [executed]], signaler: signaler)

    await assertTerminationError(.identityChanged) {
      try await terminator.terminate(self.target(for: root))
    }
    XCTAssertEqual(
      signaler.events,
      [.init(signal: .stop, pid: 550), .init(signal: .resume, pid: 550)])
  }

  func testRejectsDifferentUserWithoutSendingSignals() async {
    let root = terminationProcess(
      uid: 502, pid: 600, ppid: 10, elapsed: 20, path: "/tool/node")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(snapshots: [[root]], signaler: signaler)

    await assertTerminationError(.ownershipMismatch) {
      try await terminator.terminate(self.target(for: root))
    }
    XCTAssertTrue(signaler.events.isEmpty)
  }

  func testPermissionFailureAbortsBeforeTermAndResumesVerifiedFrozenProcesses() async {
    let root = terminationProcess(pid: 650, ppid: 10, elapsed: 20, path: "/tool/node")
    let child = terminationProcess(pid: 651, ppid: 650, elapsed: 5, path: "/tool/helper")
    let denied = ProcessSignalEvent(signal: .stop, pid: 651)
    let signaler = RecordingProcessSignaler(failures: [denied: .permissionDenied])
    let terminator = makeTerminator(
      snapshots: [[root, child], [root, child]], signaler: signaler)

    await assertTerminationError(.permissionDenied) {
      try await terminator.terminate(self.target(for: root))
    }

    XCTAssertEqual(
      signaler.events,
      [
        .init(signal: .stop, pid: 650), .init(signal: .stop, pid: 651),
        .init(signal: .resume, pid: 650),
      ])
  }

  func testRejectsAProcessThatOwnsTheRunningWatchioInstance() async {
    let root = terminationProcess(pid: 700, ppid: 10, elapsed: 20, path: "/tool/codex")
    let watchio = terminationProcess(
      pid: 900, ppid: 700, elapsed: 5, path: "/Applications/Watchio.app/Watchio")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(
      snapshots: [[root, watchio]], signaler: signaler, currentProcessID: 900)

    await assertTerminationError(.protectedProcess) {
      try await terminator.terminate(self.target(for: root))
    }
    XCTAssertTrue(signaler.events.isEmpty)
  }

  func testUnstableTreeFailsBeforeTermAndResumesEverythingFrozen() async {
    let root = terminationProcess(pid: 800, ppid: 10, elapsed: 30, path: "/tool/node")
    let child = terminationProcess(pid: 801, ppid: 800, elapsed: 10, path: "/tool/helper")
    let grandchild = terminationProcess(pid: 802, ppid: 801, elapsed: 2, path: "/tool/tail")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(
      snapshots: [[root], [root, child], [root, child, grandchild]], signaler: signaler,
      freezePasses: 2)

    await assertTerminationError(.treeDidNotStabilize) {
      try await terminator.terminate(self.target(for: root))
    }
    XCTAssertFalse(signaler.events.contains { $0.signal == .terminate || $0.signal == .kill })
    XCTAssertEqual(
      Set(signaler.events.filter { $0.signal == .resume }.map(\.pid)), Set([800, 801, 802]))
  }

  func testReportsSurvivorWhenVerifiedProcessRemainsAfterSIGKILL() async throws {
    let root = terminationProcess(pid: 1_000, ppid: 10, elapsed: 30, path: "/tool/node")
    let signaler = RecordingProcessSignaler()
    let terminator = makeTerminator(
      snapshots: [[root], [root], [root], [root], [root]], signaler: signaler,
      gracePollAttempts: 1, finalPollAttempts: 1)

    let result = try await terminator.terminate(target(for: root))

    XCTAssertEqual(result.forceKilledProcessCount, 1)
    XCTAssertEqual(result.survivingProcessCount, 1)
  }

  func testInventoryFailureAfterTermReportsAnUnverifiedOutcome() async {
    let root = terminationProcess(pid: 1_100, ppid: 10, elapsed: 30, path: "/tool/node")
    let signaler = RecordingProcessSignaler()
    let fixedNow = observedAt
    let terminator = ProcessTreeTerminator(
      processProvider: FailingProcessProvider(successfulSnapshots: [[root], [root]]),
      signaler: signaler, currentUID: 501, currentProcessID: 9_999, now: { fixedNow },
      sleeper: { _ in }, freezeSettleInterval: .zero, pollInterval: .zero)

    await assertTerminationError(.outcomeUnverified) {
      try await terminator.terminate(self.target(for: root))
    }
    XCTAssertTrue(signaler.events.contains(.init(signal: .terminate, pid: 1_100)))
    XCTAssertFalse(signaler.events.contains(.init(signal: .kill, pid: 1_100)))
  }

  private func makeTerminator(
    snapshots: [[ProcessRecord]], signaler: RecordingProcessSignaler,
    currentProcessID: Int32 = 9_999, freezePasses: Int = 4, gracePollAttempts: Int = 1,
    finalPollAttempts: Int = 1
  ) -> ProcessTreeTerminator {
    let fixedNow = observedAt
    return ProcessTreeTerminator(
      processProvider: SequencedProcessProvider(snapshots), signaler: signaler, currentUID: 501,
      currentProcessID: currentProcessID, now: { fixedNow }, sleeper: { _ in },
      freezePasses: freezePasses, gracePollAttempts: gracePollAttempts,
      finalPollAttempts: finalPollAttempts, freezeSettleInterval: .zero, pollInterval: .zero
    )
  }

  private func target(for process: ProcessRecord) -> ProcessTerminationTarget {
    ProcessTerminationTarget(
      representativePID: process.pid,
      representativeStartedAt: observedAt.addingTimeInterval(-process.elapsedSeconds))
  }

  private func assertTerminationError(
    _ expected: ProcessTreeTerminationError,
    operation: () async throws -> ProcessTerminationResult
  ) async {
    do {
      _ = try await operation()
      XCTFail("Expected \(expected)")
    } catch let error as ProcessTreeTerminationError {
      XCTAssertEqual(error, expected)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}

private actor SequencedProcessProvider: ProcessInventoryProviding {
  private var snapshots: [[ProcessRecord]]

  init(_ snapshots: [[ProcessRecord]]) {
    self.snapshots = snapshots
  }

  func processes() async throws -> [ProcessRecord] {
    guard snapshots.count > 1 else { return snapshots.first ?? [] }
    return snapshots.removeFirst()
  }
}

private actor FailingProcessProvider: ProcessInventoryProviding {
  private var successfulSnapshots: [[ProcessRecord]]

  init(successfulSnapshots: [[ProcessRecord]]) {
    self.successfulSnapshots = successfulSnapshots
  }

  func processes() async throws -> [ProcessRecord] {
    guard !successfulSnapshots.isEmpty else { throw FailingProcessProviderError.unavailable }
    return successfulSnapshots.removeFirst()
  }
}

private enum FailingProcessProviderError: Error { case unavailable }

private struct ProcessSignalEvent: Hashable {
  let signal: ProcessControlSignal
  let pid: Int32
}

private final class RecordingProcessSignaler: ProcessSignaling, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [ProcessSignalEvent] = []
  private let failures: [ProcessSignalEvent: ProcessSignalError]

  init(failures: [ProcessSignalEvent: ProcessSignalError] = [:]) {
    self.failures = failures
  }

  var events: [ProcessSignalEvent] {
    lock.withLock { storage }
  }

  func send(_ signal: ProcessControlSignal, to processID: Int32) throws {
    let event = ProcessSignalEvent(signal: signal, pid: processID)
    lock.withLock { storage.append(event) }
    if let failure = failures[event] { throw failure }
  }
}

private func terminationProcess(
  uid: uid_t = 501, pid: Int32, ppid: Int32, elapsed: TimeInterval, path: String
) -> ProcessRecord {
  ProcessRecord(
    uid: uid, pid: pid, parentPID: ppid, processGroupID: pid, tty: "ttys001",
    elapsedSeconds: elapsed, cpuPercent: 1, memoryBytes: 1_024, executablePath: path)
}
