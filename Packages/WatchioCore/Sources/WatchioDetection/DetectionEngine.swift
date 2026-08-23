import Darwin
import Foundation
import WatchioModels

public struct DetectionEngine: Sendable {
  private let processProvider: any ProcessInventoryProviding
  private let listenerProvider: any ListenerInventoryProviding
  private let containerProvider: any ContainerInventoryProviding
  private let projectResolver: any ProjectResolving
  private let currentUID: uid_t
  private let now: @Sendable () -> Date

  public init(
    processProvider: any ProcessInventoryProviding = PSProcessInventoryProvider(),
    listenerProvider: any ListenerInventoryProviding = LsofListenerInventoryProvider(),
    containerProvider: any ContainerInventoryProviding = DockerInventoryProvider(),
    projectResolver: any ProjectResolving = LsofProjectResolver(),
    currentUID: uid_t = getuid(),
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    self.processProvider = processProvider
    self.listenerProvider = listenerProvider
    self.containerProvider = containerProvider
    self.projectResolver = projectResolver
    self.currentUID = currentUID
    self.now = now
  }

  public func scan(preferences: DetectionPreferences) async -> DetectionResult {
    async let processAttempt = capture { try await processProvider.processes() }
    async let tcpListenerAttempt = capture { try await listenerProvider.tcpListeners() }
    async let containerAttempt = capture { try await containerProvider.containers() }

    let (processesResult, tcpListenersResult, containersResult) = await (
      processAttempt, tcpListenerAttempt, containerAttempt
    )
    let processes =
      (try? processesResult.get())?
      .filter { $0.uid == currentUID && $0.elapsedSeconds >= 3 } ?? []
    let tcpListeners = (try? tcpListenersResult.get()) ?? []
    let listenerPIDs = Set(tcpListeners.map(\.pid))
    let processByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })

    let serviceCandidates = processes.filter {
      ProcessClassifier.runtime(for: $0) != nil || listenerPIDs.contains($0.pid)
    }
    let aiCandidates =
      preferences.observeAIActivity
      ? processes.filter { AIProcessClassifier.tool(for: $0) != nil } : []
    let projectCandidates = Array(
      Dictionary(uniqueKeysWithValues: (serviceCandidates + aiCandidates).map { ($0.pid, $0) })
        .values)
    let projectsResult = await capture {
      try await projectResolver.projects(for: projectCandidates, roots: preferences.projectRoots)
    }
    let projects = (try? projectsResult.get()) ?? [:]

    let qualified = serviceCandidates.compactMap { process -> QualifiedProcess? in
      let classification = ProcessClassifier.classify(
        process: process,
        project: projects[process.pid],
        hasListener: listenerPIDs.contains(process.pid),
        hasDevelopmentAncestry: ProcessClassifier.hasDevelopmentAncestry(
          process: process, processByPID: processByPID
        ),
        preferences: preferences
      )
      guard !classification.isIgnored, classification.confidence >= 40 else { return nil }
      return QualifiedProcess(
        process: process, project: projects[process.pid], classification: classification)
    }

    let qualifiedGroups = Set(
      qualified.map(\.process.processGroupID).filter { $0 > 1 }
    )
    let qualifiedPIDs = Set(qualified.map(\.process.pid))
    let qualifiedProcessIDs = processes.filter { process in
      qualifiedPIDs.contains(process.pid) || qualifiedGroups.contains(process.processGroupID)
    }.map(\.pid)
    let udpListenersResult: Result<[PortRecord], any Error>
    if qualifiedProcessIDs.isEmpty {
      udpListenersResult = .success([])
    } else {
      udpListenersResult = await capture {
        try await listenerProvider.udpBindings(for: qualifiedProcessIDs)
      }
    }
    let udpListeners = (try? udpListenersResult.get()) ?? []
    let listeners = Array(Set(tcpListeners + udpListeners))

    var services: [DetectedService] = []
    var suggestions: [ReviewSuggestion] = []
    let grouped = Dictionary(grouping: qualified, by: groupKey)
    for group in grouped.values {
      let service = makeService(group: group, allProcesses: processes, listeners: listeners)
      if service.confidence >= 60 {
        services.append(service)
      } else {
        suggestions.append(ReviewSuggestion(service: service))
      }
    }

    if preferences.enabledRuntimes.contains(.docker),
      case .success(let containers) = containersResult
    {
      services.append(contentsOf: containers.map(makeContainerService))
    }

    let aiActivities =
      preferences.observeAIActivity
      ? makeAIActivities(
        candidates: aiCandidates, allProcesses: processes, projects: projects,
        processByPID: processByPID)
      : []

    services.sort(by: serviceSort)
    suggestions.sort { serviceSort($0.service, $1.service) }
    return DetectionResult(
      services: services,
      aiActivities: aiActivities,
      reviewSuggestions: suggestions,
      sourceHealth: [
        health(.processes, result: processesResult),
        listenerHealth(tcp: tcpListenersResult, udp: udpListenersResult),
        health(.projects, result: projectsResult),
        health(.docker, result: containersResult, optional: true),
      ]
    )
  }

  private func makeAIActivities(
    candidates: [ProcessRecord], allProcesses: [ProcessRecord], projects: [Int32: ProjectContext],
    processByPID: [Int32: ProcessRecord]
  ) -> [DetectedAIActivity] {
    let qualified = candidates.compactMap { process -> QualifiedAIProcess? in
      guard
        let classification = AIProcessClassifier.classify(
          process: process, project: projects[process.pid], processByPID: processByPID),
        classification.confidence >= 60
      else { return nil }
      return QualifiedAIProcess(
        process: process, project: projects[process.pid], classification: classification)
    }
    let rootPIDs = Set(qualified.map(\.process.pid))
    var membersByRoot: [Int32: [ProcessRecord]] = [:]
    for process in allProcesses {
      guard
        let rootPID = nearestAIRoot(
          for: process, rootPIDs: rootPIDs, processByPID: processByPID)
      else { continue }
      membersByRoot[rootPID, default: []].append(process)
    }

    return qualified.map { root in
      let members = membersByRoot[root.process.pid] ?? [root.process]
      let elapsed = members.map(\.elapsedSeconds).max() ?? root.process.elapsedSeconds
      return DetectedAIActivity(
        id: StableIdentifier.make([
          "ai", root.classification.tool.rawValue, String(root.process.pid),
          String(root.process.processGroupID), root.project?.rootPath ?? "",
        ]),
        tool: root.classification.tool,
        host: root.classification.host,
        projectName: root.project?.name,
        projectPath: root.project?.displayPath,
        representativePID: root.process.pid,
        processCount: members.count,
        tty: root.process.tty,
        cpuPercent: members.reduce(0) { $0 + $1.cpuPercent },
        memoryBytes: members.reduce(0) { $0 + $1.memoryBytes },
        startedAt: now().addingTimeInterval(-elapsed),
        confidence: root.classification.confidence,
        evidence: root.classification.evidence
      )
    }.sorted(by: aiActivitySort)
  }

  private func nearestAIRoot(
    for process: ProcessRecord, rootPIDs: Set<Int32>, processByPID: [Int32: ProcessRecord],
    maximumDepth: Int = 48
  ) -> Int32? {
    var current = process
    var visited: Set<Int32> = []
    for _ in 0..<maximumDepth {
      guard visited.insert(current.pid).inserted else { return nil }
      if rootPIDs.contains(current.pid) { return current.pid }
      guard let parent = processByPID[current.parentPID] else { return nil }
      current = parent
    }
    return nil
  }

  private func aiActivitySort(_ lhs: DetectedAIActivity, _ rhs: DetectedAIActivity) -> Bool {
    if lhs.tool.displayName != rhs.tool.displayName {
      return lhs.tool.displayName.localizedCaseInsensitiveCompare(rhs.tool.displayName)
        == .orderedAscending
    }
    if lhs.projectName != rhs.projectName {
      return (lhs.projectName ?? "").localizedCaseInsensitiveCompare(rhs.projectName ?? "")
        == .orderedAscending
    }
    return lhs.id < rhs.id
  }

  private func groupKey(_ item: QualifiedProcess) -> String {
    let project = item.project?.rootPath ?? "unresolved"
    let group = item.process.processGroupID > 1 ? item.process.processGroupID : item.process.pid
    return "\(project)|\(group)"
  }

  private func makeService(
    group: [QualifiedProcess], allProcesses: [ProcessRecord], listeners: [PortRecord]
  ) -> DetectedService {
    let representative = group.sorted {
      if $0.classification.confidence != $1.classification.confidence {
        return $0.classification.confidence > $1.classification.confidence
      }
      return $0.process.pid < $1.process.pid
    }[0]
    let processGroupID = representative.process.processGroupID
    let memberProcesses = allProcesses.filter {
      processGroupID > 1
        ? $0.processGroupID == processGroupID : $0.pid == representative.process.pid
    }
    let memberPIDs = Set(memberProcesses.map(\.pid))
    let matchingListeners = listeners.filter { memberPIDs.contains($0.pid) }
    let uniqueEndpoints = Set(matchingListeners.map(\.endpoint))
    let ports = Array(uniqueEndpoints).sorted {
      $0.port == $1.port ? $0.transport.rawValue < $1.transport.rawValue : $0.port < $1.port
    }
    let project = representative.project
    let runtime = representative.classification.runtime
    let projectName = project?.name ?? representative.process.executableName
    let confidence = group.map(\.classification.confidence).max() ?? 0
    let evidence = Array(Set(group.flatMap(\.classification.evidence))).sorted {
      $0.rawValue < $1.rawValue
    }
    let earliestElapsed =
      memberProcesses.map(\.elapsedSeconds).max() ?? representative.process.elapsedSeconds

    return DetectedService(
      id: StableIdentifier.make([project?.rootPath ?? "", String(processGroupID), runtime.rawValue]
      ),
      name: project == nil
        ? representative.process.executableName : "\(projectName) · \(runtime.displayName)",
      projectName: projectName,
      projectPath: project?.displayPath,
      runtime: runtime,
      representativePID: representative.process.pid,
      processCount: memberProcesses.count,
      ports: ports,
      cpuPercent: memberProcesses.reduce(0) { $0 + $1.cpuPercent },
      memoryBytes: memberProcesses.reduce(0) { $0 + $1.memoryBytes },
      startedAt: now().addingTimeInterval(-earliestElapsed),
      confidence: confidence,
      evidence: evidence
    )
  }

  private func makeContainerService(_ container: ContainerRecord) -> DetectedService {
    DetectedService(
      id: StableIdentifier.make(["docker", container.id]),
      name: container.name,
      projectName: container.projectName,
      projectPath: container.projectPath,
      runtime: .docker,
      representativePID: nil,
      processCount: 1,
      ports: container.ports,
      cpuPercent: nil,
      memoryBytes: nil,
      startedAt: container.startedAt,
      confidence: 100,
      evidence: container.ports.isEmpty ? [.dockerMetadata] : [.dockerMetadata, .listeningEndpoint]
    )
  }

  private func serviceSort(_ lhs: DetectedService, _ rhs: DetectedService) -> Bool {
    if lhs.projectName != rhs.projectName {
      return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
    }
    if lhs.name != rhs.name {
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    return lhs.id < rhs.id
  }

  private func health<T>(
    _ source: InventorySource, result: Result<T, any Error>, optional: Bool = false
  ) -> SourceHealth {
    switch result {
    case .success:
      return SourceHealth(source: source, state: .available)
    case .failure(let error):
      return SourceHealth(
        source: source,
        state: optional ? .degraded : .unavailable,
        message: sanitizedError(error)
      )
    }
  }

  private func listenerHealth(
    tcp: Result<[PortRecord], any Error>, udp: Result<[PortRecord], any Error>
  ) -> SourceHealth {
    switch (tcp, udp) {
    case (.success, .success):
      SourceHealth(source: .listeners, state: .available)
    case (.success, .failure(let error)):
      SourceHealth(source: .listeners, state: .degraded, message: sanitizedError(error))
    case (.failure(let error), _):
      SourceHealth(source: .listeners, state: .unavailable, message: sanitizedError(error))
    }
  }

  private func sanitizedError(_ error: any Error) -> String {
    switch error {
    case InventoryError.commandTimedOut: "Timed out"
    case InventoryError.outputLimitExceeded: "Output limit reached"
    case InventoryError.unavailable: "Not installed or unavailable"
    case InventoryError.commandFailed: "Command unavailable"
    case InventoryError.malformedOutput: "Unexpected output"
    default: "Unavailable"
    }
  }

  private func capture<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T
  ) async -> Result<T, any Error> {
    do { return .success(try await operation()) } catch { return .failure(error) }
  }
}

private struct QualifiedProcess: Sendable {
  let process: ProcessRecord
  let project: ProjectContext?
  let classification: Classification
}

private struct QualifiedAIProcess: Sendable {
  let process: ProcessRecord
  let project: ProjectContext?
  let classification: AIProcessClassification
}
