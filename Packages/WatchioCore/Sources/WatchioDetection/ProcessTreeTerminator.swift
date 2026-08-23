import Darwin
import Foundation
import WatchioModels

public struct ProcessTerminationTarget: Hashable, Sendable {
  public let representativePID: Int32
  public let representativeStartedAt: Date

  public init(representativePID: Int32, representativeStartedAt: Date) {
    self.representativePID = representativePID
    self.representativeStartedAt = representativeStartedAt
  }
}

public struct ProcessTerminationResult: Hashable, Sendable {
  public let trackedProcessCount: Int
  public let forceKilledProcessCount: Int
  public let survivingProcessCount: Int

  public init(
    trackedProcessCount: Int, forceKilledProcessCount: Int, survivingProcessCount: Int
  ) {
    self.trackedProcessCount = trackedProcessCount
    self.forceKilledProcessCount = forceKilledProcessCount
    self.survivingProcessCount = survivingProcessCount
  }

  public var terminatedProcessCount: Int {
    max(0, trackedProcessCount - survivingProcessCount)
  }
}

public enum ProcessTreeTerminationError: Error, LocalizedError, Equatable, Sendable {
  case invalidTarget
  case processNotFound
  case ownershipMismatch
  case identityChanged
  case protectedProcess
  case treeDidNotStabilize
  case inventoryUnavailable
  case outcomeUnverified
  case permissionDenied
  case signalFailed

  public var errorDescription: String? {
    switch self {
    case .invalidTarget: "Watchio refused an invalid process target."
    case .processNotFound: "The process already exited."
    case .ownershipMismatch: "Watchio can stop only processes owned by the current user."
    case .identityChanged: "The PID now belongs to a different process. Nothing was stopped."
    case .protectedProcess:
      "Watchio will not stop itself or a process that owns this Watchio instance."
    case .treeDidNotStabilize: "The process tree kept changing. Nothing was stopped."
    case .inventoryUnavailable: "Watchio could not verify the current process tree."
    case .outcomeUnverified:
      "Watchio sent SIGTERM but could not verify the final state. Some processes may still be alive."
    case .permissionDenied: "macOS refused permission to stop one of the verified processes."
    case .signalFailed: "macOS could not signal one of the verified processes."
    }
  }
}

public enum ProcessControlSignal: Hashable, Sendable {
  case stop
  case terminate
  case resume
  case kill

  fileprivate var posixValue: Int32 {
    switch self {
    case .stop: SIGSTOP
    case .terminate: SIGTERM
    case .resume: SIGCONT
    case .kill: SIGKILL
    }
  }
}

public enum ProcessSignalError: Error, Equatable, Sendable {
  case noSuchProcess
  case permissionDenied
  case failed
}

public protocol ProcessSignaling: Sendable {
  func send(_ signal: ProcessControlSignal, to processID: Int32) throws
}

public struct POSIXProcessSignaler: ProcessSignaling {
  public init() {}

  public func send(_ signal: ProcessControlSignal, to processID: Int32) throws {
    guard Darwin.kill(processID, signal.posixValue) == 0 else {
      switch errno {
      case ESRCH: throw ProcessSignalError.noSuchProcess
      case EPERM: throw ProcessSignalError.permissionDenied
      default: throw ProcessSignalError.failed
      }
    }
  }
}

public struct ProcessTreeTerminator: Sendable {
  public typealias Sleeper = @Sendable (Duration) async -> Void

  private let processProvider: any ProcessInventoryProviding
  private let signaler: any ProcessSignaling
  private let currentUID: uid_t
  private let currentProcessID: Int32
  private let now: @Sendable () -> Date
  private let sleeper: Sleeper
  private let freezePasses: Int
  private let gracePollAttempts: Int
  private let finalPollAttempts: Int
  private let freezeSettleInterval: Duration
  private let pollInterval: Duration
  private let identityTolerance: TimeInterval

  public init(
    processProvider: any ProcessInventoryProviding = PSProcessInventoryProvider(),
    signaler: any ProcessSignaling = POSIXProcessSignaler(), currentUID: uid_t = getuid(),
    currentProcessID: Int32 = getpid(), now: @escaping @Sendable () -> Date = { .now },
    sleeper: @escaping Sleeper = { duration in try? await Task.sleep(for: duration) },
    freezePasses: Int = 4, gracePollAttempts: Int = 25, finalPollAttempts: Int = 10,
    freezeSettleInterval: Duration = .milliseconds(25), pollInterval: Duration = .milliseconds(200),
    identityTolerance: TimeInterval = 3
  ) {
    self.processProvider = processProvider
    self.signaler = signaler
    self.currentUID = currentUID
    self.currentProcessID = currentProcessID
    self.now = now
    self.sleeper = sleeper
    self.freezePasses = max(1, freezePasses)
    self.gracePollAttempts = max(0, gracePollAttempts)
    self.finalPollAttempts = max(1, finalPollAttempts)
    self.freezeSettleInterval = freezeSettleInterval
    self.pollInterval = pollInterval
    self.identityTolerance = max(1, identityTolerance)
  }

  public func terminate(_ target: ProcessTerminationTarget) async throws
    -> ProcessTerminationResult
  {
    guard target.representativePID > 1 else { throw ProcessTreeTerminationError.invalidTarget }
    let initialObservedAt = now()
    let initialProcesses = try await inventory()
    guard let root = initialProcesses.first(where: { $0.pid == target.representativePID }) else {
      throw ProcessTreeTerminationError.processNotFound
    }
    guard root.uid == currentUID else { throw ProcessTreeTerminationError.ownershipMismatch }
    guard matchesStart(root, expected: target.representativeStartedAt, at: initialObservedAt) else {
      throw ProcessTreeTerminationError.identityChanged
    }

    let protectedProcessIDs = protectedProcessIDs(in: initialProcesses)
    guard !protectedProcessIDs.contains(root.pid) else {
      throw ProcessTreeTerminationError.protectedProcess
    }

    var identities: [Int32: ProcessIdentity] = [
      root.pid: ProcessIdentity(record: root, observedAt: initialObservedAt)
    ]
    var depths: [Int32: Int] = [root.pid: 0]
    var frozen: Set<Int32> = []

    do {
      guard try send(.stop, to: root.pid) else {
        throw ProcessTreeTerminationError.processNotFound
      }
      frozen.insert(root.pid)

      var stabilized = false
      for _ in 0..<freezePasses {
        await sleeper(freezeSettleInterval)
        let observedAt = now()
        let processes = try await inventory()
        guard let currentRoot = processes.first(where: { $0.pid == root.pid }) else {
          frozen.remove(root.pid)
          throw ProcessTreeTerminationError.processNotFound
        }
        guard
          identities[root.pid]?.matches(
            currentRoot, at: observedAt, tolerance: identityTolerance) == true
        else {
          resumeIfSameKernelProcess(
            identities[root.pid], current: currentRoot, observedAt: observedAt)
          frozen.remove(root.pid)
          throw ProcessTreeTerminationError.identityChanged
        }

        for (processID, identity) in Array(identities) {
          guard let current = processes.first(where: { $0.pid == processID }) else {
            identities.removeValue(forKey: processID)
            depths.removeValue(forKey: processID)
            frozen.remove(processID)
            continue
          }
          guard identity.matches(current, at: observedAt, tolerance: identityTolerance) else {
            resumeIfSameKernelProcess(identity, current: current, observedAt: observedAt)
            frozen.remove(processID)
            throw ProcessTreeTerminationError.identityChanged
          }
        }

        let treeDepths = descendantDepths(rootPID: root.pid, processes: processes)
        var discovered = false
        for process in processes.sorted(by: { $0.pid < $1.pid }) {
          guard let depth = treeDepths[process.pid], process.uid == currentUID,
            !protectedProcessIDs.contains(process.pid), identities[process.pid] == nil
          else { continue }
          if try send(.stop, to: process.pid) {
            identities[process.pid] = ProcessIdentity(record: process, observedAt: observedAt)
            depths[process.pid] = depth
            frozen.insert(process.pid)
            discovered = true
          }
        }
        if !discovered {
          stabilized = true
          break
        }
      }
      guard stabilized else { throw ProcessTreeTerminationError.treeDidNotStabilize }

      for processID in identities.keys.sorted(by: { (depths[$0] ?? 0) > (depths[$1] ?? 0) }) {
        _ = try send(.terminate, to: processID)
      }
      for processID in frozen.sorted(by: { (depths[$0] ?? 0) > (depths[$1] ?? 0) }) {
        _ = try send(.resume, to: processID)
        frozen.remove(processID)
      }
    } catch {
      resume(processIDs: frozen)
      throw error
    }

    var forceKilled: Set<Int32> = []
    for _ in 0..<gracePollAttempts {
      if !Task.isCancelled { await sleeper(pollInterval) }
      let observedAt = now()
      let processes = try await postTerminationInventory()
      var active = activeIdentities(identities, in: processes, observedAt: observedAt)
      if active.isEmpty {
        return ProcessTerminationResult(
          trackedProcessCount: identities.count, forceKilledProcessCount: 0,
          survivingProcessCount: 0)
      }

      let processByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
      let activeIDs = Set(active.keys)
      for process in processes where process.uid == currentUID && identities[process.pid] == nil {
        guard !protectedProcessIDs.contains(process.pid),
          let parentDepth = nearestTrackedAncestorDepth(
            of: process, activeProcessIDs: activeIDs, processByPID: processByPID, depths: depths)
        else { continue }
        identities[process.pid] = ProcessIdentity(record: process, observedAt: observedAt)
        depths[process.pid] = parentDepth + 1
        if try send(.terminate, to: process.pid) { active[process.pid] = process }
      }
    }

    var observedAt = now()
    var processes = try await postTerminationInventory()
    var active = activeIdentities(identities, in: processes, observedAt: observedAt)
    for processID in active.keys.sorted(by: { (depths[$0] ?? 0) > (depths[$1] ?? 0) }) {
      if try send(.kill, to: processID) { forceKilled.insert(processID) }
    }

    for _ in 0..<finalPollAttempts {
      if !Task.isCancelled { await sleeper(pollInterval) }
      observedAt = now()
      processes = try await postTerminationInventory()
      active = activeIdentities(identities, in: processes, observedAt: observedAt)
      if active.isEmpty { break }
    }

    return ProcessTerminationResult(
      trackedProcessCount: identities.count,
      forceKilledProcessCount: forceKilled.count,
      survivingProcessCount: active.count)
  }

  private func inventory() async throws -> [ProcessRecord] {
    do {
      return try await processProvider.processes()
    } catch {
      throw ProcessTreeTerminationError.inventoryUnavailable
    }
  }

  private func postTerminationInventory() async throws -> [ProcessRecord] {
    do {
      return try await inventory()
    } catch {
      throw ProcessTreeTerminationError.outcomeUnverified
    }
  }

  private func send(_ signal: ProcessControlSignal, to processID: Int32) throws -> Bool {
    do {
      try signaler.send(signal, to: processID)
      return true
    } catch ProcessSignalError.noSuchProcess {
      return false
    } catch ProcessSignalError.permissionDenied {
      throw ProcessTreeTerminationError.permissionDenied
    } catch {
      throw ProcessTreeTerminationError.signalFailed
    }
  }

  private func resume(processIDs: Set<Int32>) {
    for processID in processIDs { try? signaler.send(.resume, to: processID) }
  }

  private func resumeIfSameKernelProcess(
    _ identity: ProcessIdentity?, current: ProcessRecord, observedAt: Date
  ) {
    guard
      identity?.matchesKernelProcess(
        current, at: observedAt, tolerance: identityTolerance) == true
    else { return }
    try? signaler.send(.resume, to: current.pid)
  }

  private func matchesStart(_ process: ProcessRecord, expected: Date, at observedAt: Date) -> Bool {
    abs(observedAt.addingTimeInterval(-process.elapsedSeconds).timeIntervalSince(expected))
      <= identityTolerance
  }

  private func protectedProcessIDs(in processes: [ProcessRecord]) -> Set<Int32> {
    let processByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
    var result: Set<Int32> = [currentProcessID]
    var processID = currentProcessID
    for _ in 0..<64 {
      guard let process = processByPID[processID], process.parentPID > 0,
        result.insert(process.parentPID).inserted
      else { break }
      processID = process.parentPID
    }
    return result
  }

  private func descendantDepths(rootPID: Int32, processes: [ProcessRecord]) -> [Int32: Int] {
    let processByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
    var result: [Int32: Int] = [rootPID: 0]
    for process in processes where process.pid != rootPID {
      var current = process
      var visited: Set<Int32> = []
      for depth in 1...64 {
        guard visited.insert(current.pid).inserted,
          let parent = processByPID[current.parentPID]
        else { break }
        if parent.pid == rootPID {
          result[process.pid] = depth
          break
        }
        current = parent
      }
    }
    return result
  }

  private func activeIdentities(
    _ identities: [Int32: ProcessIdentity], in processes: [ProcessRecord], observedAt: Date
  ) -> [Int32: ProcessRecord] {
    processes.reduce(into: [:]) { result, process in
      guard let identity = identities[process.pid],
        identity.matches(process, at: observedAt, tolerance: identityTolerance)
      else { return }
      result[process.pid] = process
    }
  }

  private func nearestTrackedAncestorDepth(
    of process: ProcessRecord, activeProcessIDs: Set<Int32>,
    processByPID: [Int32: ProcessRecord], depths: [Int32: Int]
  ) -> Int? {
    var parentPID = process.parentPID
    var visited: Set<Int32> = [process.pid]
    for _ in 0..<64 {
      guard visited.insert(parentPID).inserted else { return nil }
      if activeProcessIDs.contains(parentPID) { return depths[parentPID] ?? 0 }
      guard let parent = processByPID[parentPID] else { return nil }
      parentPID = parent.parentPID
    }
    return nil
  }
}

private struct ProcessIdentity: Hashable, Sendable {
  let pid: Int32
  let uid: uid_t
  let executablePath: String
  let startedAt: Date

  init(record: ProcessRecord, observedAt: Date) {
    pid = record.pid
    uid = record.uid
    executablePath = record.executablePath
    startedAt = observedAt.addingTimeInterval(-record.elapsedSeconds)
  }

  func matches(_ record: ProcessRecord, at observedAt: Date, tolerance: TimeInterval) -> Bool {
    guard executablePath == record.executablePath else { return false }
    return matchesKernelProcess(record, at: observedAt, tolerance: tolerance)
  }

  func matchesKernelProcess(
    _ record: ProcessRecord, at observedAt: Date, tolerance: TimeInterval
  ) -> Bool {
    guard record.pid == pid, record.uid == uid else { return false }
    let inferredStart = observedAt.addingTimeInterval(-record.elapsedSeconds)
    return abs(inferredStart.timeIntervalSince(startedAt)) <= tolerance
  }
}
