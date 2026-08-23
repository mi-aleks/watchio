import Foundation
import IOKit.ps
import WatchioModels

public enum PowerSourceState: Hashable, Sendable {
  case battery
  case externalPower
  case unknown
}

public protocol PowerSourceProviding: Sendable {
  func currentPowerSource() -> PowerSourceState
}

public struct SystemPowerSourceProvider: PowerSourceProviding {
  public init() {}

  public func currentPowerSource() -> PowerSourceState {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as? String
    else { return .unknown }
    if source == kIOPMBatteryPowerKey { return .battery }
    if source == kIOPMACPowerKey || source == kIOPMUPSPowerKey { return .externalPower }
    return .unknown
  }
}

public struct ResourceAlertEvaluator: Sendable {
  public struct Configuration: Hashable, Sendable {
    public var activationSamples: Int
    public var recoverySamples: Int
    public var recoveryRatio: Double

    public init(activationSamples: Int = 3, recoverySamples: Int = 2, recoveryRatio: Double = 0.8) {
      self.activationSamples = max(1, activationSamples)
      self.recoverySamples = max(1, recoverySamples)
      self.recoveryRatio = min(max(recoveryRatio, 0.1), 0.95)
    }
  }

  private struct Key: Hashable, Sendable {
    let kind: ResourceAlertKind
    let subjectKind: ResourceAlertSubjectKind
    let subjectID: String
  }

  private struct State: Sendable {
    var highSamples = 0
    var lowSamples = 0
    var firstHighAt: Date?
    var activeSince: Date?
  }

  private struct Subject: Sendable {
    let kind: ResourceAlertSubjectKind
    let id: String
    let name: String
    let memoryBytes: UInt64?
    let cpuPercent: Double?
  }

  private let configuration: Configuration
  private var states: [Key: State] = [:]

  public init(configuration: Configuration = Configuration()) {
    self.configuration = configuration
  }

  public mutating func reset() {
    states.removeAll(keepingCapacity: true)
  }

  public mutating func evaluate(
    services: [DetectedService], aiActivities: [DetectedAIActivity],
    preferences: DetectionPreferences, powerSource: PowerSourceState, at date: Date = .now
  ) -> [ResourceAlert] {
    guard preferences.resourceAlertsEnabled else {
      reset()
      return []
    }

    let memoryThreshold = max(preferences.memoryAlertThresholdBytes, 128 * 1_024 * 1_024)
    let cpuThreshold = max(preferences.energyAlertCPUThresholdPercent, 5)
    let subjects = makeSubjects(services: services, aiActivities: aiActivities)
    var observedKeys = Set<Key>()
    var alerts: [ResourceAlert] = []

    for subject in subjects {
      if let memoryBytes = subject.memoryBytes {
        let key = Key(kind: .memory, subjectKind: subject.kind, subjectID: subject.id)
        observedKeys.insert(key)
        if let activeSince = update(
          key: key, value: Double(memoryBytes), threshold: Double(memoryThreshold), at: date)
        {
          alerts.append(
            ResourceAlert(
              kind: .memory, subjectKind: subject.kind, subjectID: subject.id,
              subjectName: subject.name, memoryBytes: memoryBytes,
              thresholdMemoryBytes: memoryThreshold, detectedAt: activeSince))
        }
      }

      if powerSource == .battery, let cpuPercent = subject.cpuPercent {
        let key = Key(kind: .energy, subjectKind: subject.kind, subjectID: subject.id)
        observedKeys.insert(key)
        if let activeSince = update(
          key: key, value: cpuPercent, threshold: cpuThreshold, at: date)
        {
          alerts.append(
            ResourceAlert(
              kind: .energy, subjectKind: subject.kind, subjectID: subject.id,
              subjectName: subject.name, cpuPercent: cpuPercent,
              thresholdCPUPercent: cpuThreshold, detectedAt: activeSince))
        }
      }
    }

    states = states.filter { observedKeys.contains($0.key) }
    return alerts.sorted { severityRatio($0) > severityRatio($1) }
  }

  private mutating func update(key: Key, value: Double, threshold: Double, at date: Date) -> Date? {
    var state = states[key] ?? State()
    if value >= threshold {
      state.highSamples += 1
      state.lowSamples = 0
      if state.firstHighAt == nil { state.firstHighAt = date }
      if state.activeSince == nil, state.highSamples >= configuration.activationSamples {
        state.activeSince = state.firstHighAt ?? date
      }
    } else if state.activeSince != nil, value < threshold * configuration.recoveryRatio {
      state.highSamples = 0
      state.lowSamples += 1
      if state.lowSamples >= configuration.recoverySamples {
        state = State()
      }
    } else if state.activeSince == nil {
      state = State()
    } else {
      state.highSamples = 0
      state.lowSamples = 0
    }
    states[key] = state
    return state.activeSince
  }

  private func makeSubjects(
    services: [DetectedService], aiActivities: [DetectedAIActivity]
  ) -> [Subject] {
    let serviceSubjects = services.map {
      Subject(
        kind: .service, id: $0.id, name: $0.name, memoryBytes: $0.memoryBytes,
        cpuPercent: $0.cpuPercent)
    }
    let aiSubjects = aiActivities.map { activity in
      Subject(
        kind: .aiActivity, id: activity.id,
        name: activity.projectName.map { "\(activity.tool.displayName) · \($0)" }
          ?? activity.tool.displayName,
        memoryBytes: activity.memoryBytes, cpuPercent: activity.cpuPercent)
    }
    return serviceSubjects + aiSubjects
  }

  private func severityRatio(_ alert: ResourceAlert) -> Double {
    switch alert.kind {
    case .memory:
      guard let value = alert.memoryBytes, let threshold = alert.thresholdMemoryBytes else {
        return 0
      }
      return Double(value) / Double(max(threshold, 1))
    case .energy:
      guard let value = alert.cpuPercent, let threshold = alert.thresholdCPUPercent else {
        return 0
      }
      return value / max(threshold, 0.1)
    }
  }
}
