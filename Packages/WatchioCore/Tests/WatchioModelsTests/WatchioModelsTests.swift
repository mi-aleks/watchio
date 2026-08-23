import Foundation
import XCTest

@testable import WatchioModels

final class WatchioModelsTests: XCTestCase {
  func testSnapshotRoundTripAndSchemaContract() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(WatchioSnapshot.self, from: encoder.encode(DemoData.snapshot))
    XCTAssertEqual(decoded.schemaVersion, WatchioSnapshot.currentSchemaVersion)
    XCTAssertEqual(decoded.services.count, 4)
    XCTAssertEqual(decoded.aiActivities.count, 4)
    XCTAssertEqual(decoded.resourceAlerts.map(\.id), ["memory:service:demo-web"])
    XCTAssertTrue(
      decoded.services.filter { $0.representativePID != nil }
        .allSatisfy { $0.representativeStartedAt != nil })
    XCTAssertTrue(decoded.aiActivities.allSatisfy { $0.representativeStartedAt <= .now })
    XCTAssertTrue(decoded.isCompatible)
  }

  func testDemoSnapshotContainsNoPrivateMachineData() throws {
    let text = String(decoding: try JSONEncoder().encode(DemoData.snapshot), as: UTF8.self)
    XCTAssertFalse(text.contains("/Users/"))
    XCTAssertFalse(text.lowercased().contains("environment"))
    XCTAssertFalse(text.lowercased().contains("commandline"))
    XCTAssertFalse(text.lowercased().contains("arguments"))
    XCTAssertFalse(text.lowercased().contains("prompt"))
  }

  func testStableIdentifiersAreRepeatableAndOrderSensitive() {
    XCTAssertEqual(
      StableIdentifier.make(["watchio", "web"]), StableIdentifier.make(["watchio", "web"]))
    XCTAssertNotEqual(
      StableIdentifier.make(["watchio", "web"]), StableIdentifier.make(["web", "watchio"]))
  }

  func testStalenessIsExplicit() {
    let generated = Date(timeIntervalSince1970: 1_000)
    let snapshot = WatchioSnapshot(generatedAt: generated, collectorState: .active, services: [])
    XCTAssertFalse(snapshot.isStale(referenceDate: generated.addingTimeInterval(29)))
    XCTAssertTrue(snapshot.isStale(referenceDate: generated.addingTimeInterval(31)))
  }

  func testLegacyPreferencesMigrateResourceAlertsToSafeDefaults() throws {
    let decoded = try JSONDecoder().decode(
      DetectionPreferences.self,
      from: Data(#"{"scanInterval":10,"projectRoots":[]}"#.utf8))

    XCTAssertTrue(decoded.resourceAlertsEnabled)
    XCTAssertFalse(decoded.systemNotificationsEnabled)
    XCTAssertEqual(decoded.memoryAlertThresholdBytes, 1_073_741_824)
    XCTAssertEqual(decoded.energyAlertCPUThresholdPercent, 80)
  }
}
