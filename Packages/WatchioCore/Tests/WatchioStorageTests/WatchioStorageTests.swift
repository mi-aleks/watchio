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
    XCTAssertEqual(snapshot.collectorState, .active)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: directory.path),
      [WatchioSharedContainer.snapshotFilename]
    )
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
  }
}
