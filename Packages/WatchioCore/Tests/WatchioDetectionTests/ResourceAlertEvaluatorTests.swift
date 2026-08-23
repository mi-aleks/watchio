import XCTest

@testable import WatchioDetection
@testable import WatchioModels

final class ResourceAlertEvaluatorTests: XCTestCase {
  func testMemoryAlertRequiresSustainedPressureAndCarriesSafeIdentity() {
    var evaluator = ResourceAlertEvaluator()
    let preferences = DetectionPreferences(memoryAlertThresholdBytes: 128 * 1_024 * 1_024)
    let service = makeService(memoryBytes: 256 * 1_024 * 1_024, cpuPercent: 1)
    let start = Date(timeIntervalSince1970: 1_000)

    XCTAssertTrue(
      evaluator.evaluate(
        services: [service], aiActivities: [], preferences: preferences,
        powerSource: .externalPower, at: start
      ).isEmpty)
    XCTAssertTrue(
      evaluator.evaluate(
        services: [service], aiActivities: [], preferences: preferences,
        powerSource: .externalPower, at: start.addingTimeInterval(10)
      ).isEmpty)
    let alerts = evaluator.evaluate(
      services: [service], aiActivities: [], preferences: preferences,
      powerSource: .externalPower, at: start.addingTimeInterval(20))

    XCTAssertEqual(alerts.count, 1)
    XCTAssertEqual(alerts[0].id, "memory:service:service-1")
    XCTAssertEqual(alerts[0].subjectName, "dev-server")
    XCTAssertEqual(alerts[0].detectedAt, start)
    XCTAssertNil(alerts[0].cpuPercent)
  }

  func testMemoryAlertUsesHysteresisBeforeRecovery() {
    var evaluator = ResourceAlertEvaluator()
    var preferences = DetectionPreferences(memoryAlertThresholdBytes: 256 * 1_024 * 1_024)
    let high = makeService(memoryBytes: 512 * 1_024 * 1_024, cpuPercent: 1)
    let low = makeService(memoryBytes: 128 * 1_024 * 1_024, cpuPercent: 1)
    for offset in 0..<3 {
      _ = evaluator.evaluate(
        services: [high], aiActivities: [], preferences: preferences,
        powerSource: .externalPower, at: Date(timeIntervalSince1970: Double(offset)))
    }

    XCTAssertEqual(
      evaluator.evaluate(
        services: [low], aiActivities: [], preferences: preferences,
        powerSource: .externalPower
      ).count, 1)
    XCTAssertTrue(
      evaluator.evaluate(
        services: [low], aiActivities: [], preferences: preferences,
        powerSource: .externalPower
      ).isEmpty)

    preferences.resourceAlertsEnabled = false
    XCTAssertTrue(
      evaluator.evaluate(
        services: [high], aiActivities: [], preferences: preferences,
        powerSource: .externalPower
      ).isEmpty)
  }

  func testEnergyAlertRequiresBatteryAndSustainedCPU() {
    var evaluator = ResourceAlertEvaluator()
    let preferences = DetectionPreferences(energyAlertCPUThresholdPercent: 40)
    let activity = makeAIActivity(cpuPercent: 72)

    for _ in 0..<4 {
      XCTAssertTrue(
        evaluator.evaluate(
          services: [], aiActivities: [activity], preferences: preferences,
          powerSource: .externalPower
        ).isEmpty)
    }
    for _ in 0..<2 {
      XCTAssertTrue(
        evaluator.evaluate(
          services: [], aiActivities: [activity], preferences: preferences,
          powerSource: .battery
        ).isEmpty)
    }
    let alerts = evaluator.evaluate(
      services: [], aiActivities: [activity], preferences: preferences,
      powerSource: .battery)

    XCTAssertEqual(alerts.map(\.kind), [.energy])
    XCTAssertEqual(alerts.first?.subjectKind, .aiActivity)
    XCTAssertEqual(alerts.first?.cpuPercent, 72)
  }

  func testMissingSubjectAndLeavingBatteryClearState() {
    var evaluator = ResourceAlertEvaluator(configuration: .init(activationSamples: 1))
    let preferences = DetectionPreferences(
      memoryAlertThresholdBytes: 256 * 1_024 * 1_024,
      energyAlertCPUThresholdPercent: 40)
    let service = makeService(memoryBytes: 512 * 1_024 * 1_024, cpuPercent: 72)
    XCTAssertEqual(
      evaluator.evaluate(
        services: [service], aiActivities: [], preferences: preferences, powerSource: .battery
      ).count, 2)

    XCTAssertEqual(
      evaluator.evaluate(
        services: [service], aiActivities: [], preferences: preferences,
        powerSource: .externalPower
      ).map(\.kind), [.memory])
    XCTAssertTrue(
      evaluator.evaluate(
        services: [], aiActivities: [], preferences: preferences,
        powerSource: .externalPower
      ).isEmpty)
  }

  private func makeService(memoryBytes: UInt64, cpuPercent: Double) -> DetectedService {
    DetectedService(
      id: "service-1", name: "dev-server", projectName: "project", projectPath: "~/Code/project",
      runtime: .node, representativePID: 100, processCount: 1, ports: [],
      cpuPercent: cpuPercent, memoryBytes: memoryBytes, startedAt: .now, confidence: 80,
      evidence: [.projectRoot, .supportedRuntime])
  }

  private func makeAIActivity(cpuPercent: Double) -> DetectedAIActivity {
    DetectedAIActivity(
      id: "ai-1", tool: .codex, host: .terminal, projectName: "project",
      projectPath: "~/Code/project", representativePID: 200, processCount: 1, tty: "ttys001",
      cpuPercent: cpuPercent, memoryBytes: 64 * 1_024 * 1_024, startedAt: .now,
      confidence: 90, evidence: [.knownExecutable, .terminalSession])
  }
}
