import Foundation
import Observation
import ServiceManagement
import WatchioDetection
import WatchioModels
import WatchioStorage
import WidgetKit

@MainActor
@Observable
final class AppModel {
  enum Mode: String, CaseIterable, Identifiable {
    case services = "Services"
    case ai = "AI"
    case ports = "Ports"
    case health = "Health"
    var id: Self { self }
  }

  private(set) var snapshot: WatchioSnapshot = .empty
  private(set) var trend: [ResourceSample] = []
  var preferences: DetectionPreferences
  var selectedMode: Mode = .services
  var selectedServiceID: String?
  var selectedAIActivityID: String?
  var lastError: String?
  var isScanning = false
  private(set) var hasCompletedOnboarding: Bool

  private let engine: DetectionEngine
  private let snapshotStore: any SnapshotStoring
  private let preferencesStore: DetectionPreferencesStore
  private let appDefaults: UserDefaults
  private var scanTask: Task<Void, Never>?
  private var lastWidgetSignature = ""
  private var lastWidgetReloadAt: Date = .distantPast

  init(
    demoMode: Bool = ProcessInfo.processInfo.arguments.contains("--demo-data"),
    showOnboarding: Bool = ProcessInfo.processInfo.arguments.contains("--show-onboarding"),
    engine: DetectionEngine = DetectionEngine(),
    snapshotStore: any SnapshotStoring = JSONSnapshotStore(),
    preferencesStore: DetectionPreferencesStore? = nil,
    appDefaults: UserDefaults = .standard
  ) {
    self.engine = engine
    self.snapshotStore = snapshotStore
    self.appDefaults = appDefaults
    let store = preferencesStore ?? Self.makePreferencesStore()
    self.preferencesStore = store
    preferences = store.load()
    hasCompletedOnboarding =
      !showOnboarding && (demoMode || appDefaults.bool(forKey: Self.onboardingKey))

    if demoMode {
      snapshot = DemoData.snapshot
    } else {
      startCollector()
    }
  }

  var menuBarTitle: String { "w:\(snapshot.services.count + snapshot.aiActivities.count)" }
  var selectedService: DetectedService? {
    snapshot.services.first { $0.id == selectedServiceID }
  }
  var selectedAIActivity: DetectedAIActivity? {
    snapshot.aiActivities.first { $0.id == selectedAIActivityID }
  }

  var launchAtLogin: Bool {
    SMAppService.mainApp.status == .enabled
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      lastError = nil
    } catch {
      lastError = "Launch at Login could not be updated. Check System Settings → Login Items."
    }
  }

  func startCollector() {
    guard scanTask == nil else { return }
    scanTask = Task { [weak self] in
      guard let self else { return }
      await scanNow()
      while !Task.isCancelled {
        let interval = max(5, preferences.scanInterval)
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        await scanNow()
      }
    }
  }

  func scanNow() async {
    guard !isScanning else { return }
    isScanning = true
    defer { isScanning = false }

    let result = await engine.scan(preferences: preferences)
    let degraded = result.sourceHealth.contains { $0.state != .available }
    let next = WatchioSnapshot(
      collectorState: degraded ? .degraded : .active,
      services: result.services,
      aiActivities: result.aiActivities,
      reviewSuggestions: result.reviewSuggestions,
      sourceHealth: result.sourceHealth
    )
    snapshot = next
    selectedServiceID = selectedServiceID.flatMap { id in
      next.services.contains { $0.id == id } ? id : nil
    }
    selectedAIActivityID = selectedAIActivityID.flatMap { id in
      next.aiActivities.contains { $0.id == id } ? id : nil
    }
    trend.append(
      ResourceSample(
        timestamp: next.generatedAt,
        cpuPercent: next.services.compactMap(\.cpuPercent).reduce(0, +),
        memoryBytes: next.services.compactMap(\.memoryBytes).reduce(0, +)
      ))
    trend = Array(trend.suffix(60))

    do {
      try await snapshotStore.save(next)
      lastError = nil
    } catch {
      lastError = "The widget snapshot could not be updated."
    }

    let signature = materialSignature(next)
    let freshnessHeartbeatDue = next.generatedAt.timeIntervalSince(lastWidgetReloadAt) >= 30
    if signature != lastWidgetSignature || freshnessHeartbeatDue {
      lastWidgetSignature = signature
      lastWidgetReloadAt = next.generatedAt
      WidgetCenter.shared.reloadTimelines(ofKind: "WatchioWidget")
    }
  }

  func savePreferences() {
    do {
      try preferencesStore.save(preferences)
      lastError = nil
      Task { await scanNow() }
    } catch {
      lastError = "Detection preferences could not be saved."
    }
  }

  func addProjectRoot(_ path: String) {
    guard !preferences.projectRoots.contains(path) else { return }
    preferences.projectRoots.append(path)
    preferences.projectRoots.sort()
    savePreferences()
  }

  func removeProjectRoot(_ path: String) {
    preferences.projectRoots.removeAll { $0 == path }
    savePreferences()
  }

  func addIncludeRule(_ rawRule: String) {
    guard let rule = normalizedRule(rawRule), !preferences.includeRules.contains(rule) else {
      return
    }
    preferences.includeRules.append(rule)
    preferences.includeRules.sort()
    savePreferences()
  }

  func removeIncludeRule(_ rule: String) {
    preferences.includeRules.removeAll { $0 == rule }
    savePreferences()
  }

  func addIgnoreRule(_ rawRule: String) {
    guard let rule = normalizedRule(rawRule), !preferences.ignoreRules.contains(rule) else {
      return
    }
    preferences.ignoreRules.append(rule)
    preferences.ignoreRules.sort()
    savePreferences()
  }

  func removeIgnoreRule(_ rule: String) {
    preferences.ignoreRules.removeAll { $0 == rule }
    savePreferences()
  }

  func completeOnboarding() {
    hasCompletedOnboarding = true
    appDefaults.set(true, forKey: Self.onboardingKey)
  }

  func handleDeepLink(_ url: URL) {
    guard url.scheme?.lowercased() == "watchio" else { return }
    switch url.host?.lowercased() {
    case "ai":
      selectedMode = .ai
      selectedAIActivityID = url.pathComponents.dropFirst().first
    case "ports": selectedMode = .ports
    case "health": selectedMode = .health
    case "service":
      selectedMode = .services
      selectedServiceID = url.pathComponents.dropFirst().first
    default: selectedMode = .services
    }
  }

  private func materialSignature(_ snapshot: WatchioSnapshot) -> String {
    let services = snapshot.services.map { service in
      "\(service.id):\(service.ports.map(\.id).joined(separator: ","))"
    }.joined(separator: "|")
    let aiActivities = snapshot.aiActivities.map { activity in
      "\(activity.id):\(activity.processCount)"
    }.joined(separator: "|")
    let cpuBucket = Int(snapshot.services.compactMap(\.cpuPercent).reduce(0, +) / 5)
    let memoryBucket =
      snapshot.services.compactMap(\.memoryBytes).reduce(0, +) / (64 * 1_024 * 1_024)
    let aiCPU = Int(snapshot.aiActivities.map(\.cpuPercent).reduce(0, +) / 5)
    return
      "\(snapshot.collectorState.rawValue)|\(services)|ai:\(aiActivities)|cpu:\(cpuBucket)|mem:\(memoryBucket)|aicpu:\(aiCPU)"
  }

  private func normalizedRule(_ rawRule: String) -> String? {
    let rule = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
    return rule.isEmpty ? nil : rule
  }

  private static let onboardingKey = "watchio.onboarding-complete.v1"

  private static func makePreferencesStore() -> DetectionPreferencesStore {
    if let identifier = WatchioSharedContainer.groupIdentifier(),
      let shared = DetectionPreferencesStore(appGroupIdentifier: identifier)
    {
      return shared
    }
    return DetectionPreferencesStore()
  }
}

@MainActor
enum WatchioRuntime {
  static let model = AppModel()
}

struct ResourceSample: Identifiable, Hashable {
  let timestamp: Date
  let cpuPercent: Double
  let memoryBytes: UInt64
  var id: Date { timestamp }
}
