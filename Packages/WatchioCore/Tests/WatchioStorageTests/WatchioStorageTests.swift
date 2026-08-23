import Foundation
import XCTest

@testable import WatchioModels
@testable import WatchioStorage

final class WatchioStorageTests: XCTestCase {
  func testSnapshotStoreAtomicallyRoundTripsLatestSnapshot() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("watchio-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = JSONSnapshotStore(directory: directory)
    try await store.save(DemoData.snapshot)
    let loaded = await store.load()
    guard case .snapshot(let snapshot) = loaded else {
      return XCTFail("Expected a compatible snapshot")
    }
    XCTAssertEqual(snapshot.schemaVersion, WatchioSnapshot.currentSchemaVersion)
    XCTAssertEqual(snapshot.services.map(\.id), DemoData.snapshot.services.map(\.id))
    XCTAssertEqual(snapshot.services.map(\.name), DemoData.snapshot.services.map(\.name))
    XCTAssertEqual(snapshot.services.map(\.ports), DemoData.snapshot.services.map(\.ports))
    XCTAssertEqual(snapshot.aiActivities.map(\.id), DemoData.snapshot.aiActivities.map(\.id))
    XCTAssertEqual(snapshot.aiActivities.map(\.tool), DemoData.snapshot.aiActivities.map(\.tool))
    XCTAssertEqual(snapshot.aiActivities.map(\.host), DemoData.snapshot.aiActivities.map(\.host))
    XCTAssertEqual(snapshot.resourceAlerts.map(\.id), DemoData.snapshot.resourceAlerts.map(\.id))
    XCTAssertEqual(
      snapshot.resourceAlerts.map(\.memoryBytes),
      DemoData.snapshot.resourceAlerts.map(\.memoryBytes))
    XCTAssertEqual(snapshot.collectorState, .active)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path),
      [WatchioSharedContainer.snapshotFilename]
    )
    let attributes = try FileManager.default.attributesOfItem(
      atPath: directory.appendingPathComponent(WatchioSharedContainer.snapshotFilename).path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testUnknownSnapshotSchemaFailsClosed() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("watchio-schema-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(#"{"schemaVersion":999}"#.utf8).write(
      to: directory.appendingPathComponent(WatchioSharedContainer.snapshotFilename)
    )
    let loaded = await JSONSnapshotStore(directory: directory).load()
    XCTAssertEqual(loaded, .updateRequired(foundVersion: 999))
  }

  func testLegacySnapshotFilenameFailsClosedAndIsRemovedAfterSave() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("watchio-legacy-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let legacyURL = directory.appendingPathComponent(
      try XCTUnwrap(WatchioSharedContainer.legacySnapshotFilenames.first))
    try Data(#"{"schemaVersion":1}"#.utf8).write(to: legacyURL)
    let store = JSONSnapshotStore(directory: directory)

    let legacyResult = await store.load()
    XCTAssertEqual(legacyResult, .updateRequired(foundVersion: 1))

    try await store.save(DemoData.snapshot)
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    let currentResult = await store.load()
    guard case .snapshot = currentResult else {
      return XCTFail("Expected the current snapshot after migration")
    }
  }

  func testCorruptSnapshotDoesNotLeakPartialData() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("watchio-corrupt-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(
      to: directory.appendingPathComponent(WatchioSharedContainer.snapshotFilename)
    )
    let loaded = await JSONSnapshotStore(directory: directory).load()
    XCTAssertEqual(loaded, .corrupt)
  }

  func testPreferencesUseOnlyExistingDefaultRoots() {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(
      "watchio-home-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    try? FileManager.default.createDirectory(
      at: home.appendingPathComponent("Code"), withIntermediateDirectories: true)
    XCTAssertEqual(
      DetectionPreferencesStore.defaultPreferences(homeURL: home).projectRoots,
      [home.appendingPathComponent("Code").path]
    )
  }

  func testLegacyPreferencesMigrateMissingFieldsToSafeDefaults() throws {
    let suiteName = "watchio-preferences-tests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Expected an isolated defaults suite")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(
      Data(#"{"scanInterval":30,"projectRoots":["/Users/demo/Code"]}"#.utf8),
      forKey: "watchio.detection-preferences.v1"
    )

    let preferences = DetectionPreferencesStore(defaults: defaults).load()

    XCTAssertEqual(preferences.scanInterval, 30)
    XCTAssertEqual(preferences.projectRoots, ["/Users/demo/Code"])
    XCTAssertTrue(preferences.enabledRuntimes.contains(.node))
    XCTAssertEqual(preferences.includeRules, [])
    XCTAssertEqual(preferences.ignoreRules, [])
    XCTAssertTrue(preferences.showProjectPaths)
    XCTAssertTrue(preferences.observeAIActivity)
    XCTAssertTrue(preferences.resourceAlertsEnabled)
    XCTAssertFalse(preferences.systemNotificationsEnabled)
    XCTAssertEqual(preferences.memoryAlertThresholdBytes, 1_073_741_824)
    XCTAssertEqual(preferences.energyAlertCPUThresholdPercent, 80)
  }
}
