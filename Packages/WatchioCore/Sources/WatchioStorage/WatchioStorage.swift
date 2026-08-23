import Foundation
import WatchioModels

public enum SnapshotReadResult: Sendable, Equatable {
  case snapshot(WatchioSnapshot)
  case missing
  case updateRequired(foundVersion: Int)
  case corrupt
}

public protocol SnapshotStoring: Sendable {
  func load() async -> SnapshotReadResult
  func save(_ snapshot: WatchioSnapshot) async throws
}

public enum WatchioSharedContainer {
  public static let snapshotFilename = "watchio-snapshot-v4.json"
  public static let legacySnapshotFilenames = [
    "watchio-snapshot-v3.json", "watchio-snapshot-v2.json", "watchio-snapshot-v1.json",
  ]

  public static func groupIdentifier(bundle: Bundle = .main) -> String? {
    guard let value = bundle.object(forInfoDictionaryKey: "WatchioAppGroupIdentifier") as? String,
      !value.isEmpty,
      !value.hasPrefix("$(")
    else { return nil }
    return value
  }

  public static func containerURL(fileManager: FileManager = .default, bundle: Bundle = .main)
    -> URL?
  {
    guard let identifier = groupIdentifier(bundle: bundle) else { return nil }
    return fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
  }

  public static func developmentFallbackURL(fileManager: FileManager = .default) -> URL {
    let base =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return base.appendingPathComponent("Watchio", isDirectory: true)
  }
}

public actor JSONSnapshotStore: SnapshotStoring {
  private let directory: URL
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    directory: URL = WatchioSharedContainer.containerURL()
      ?? WatchioSharedContainer.developmentFallbackURL(),
    fileManager: FileManager = .default
  ) {
    self.directory = directory
    self.fileManager = fileManager
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  public func load() async -> SnapshotReadResult {
    let url = directory.appendingPathComponent(WatchioSharedContainer.snapshotFilename)
    if fileManager.fileExists(atPath: url.path) { return readSnapshot(at: url) }
    for filename in WatchioSharedContainer.legacySnapshotFilenames {
      let legacyURL = directory.appendingPathComponent(filename)
      if fileManager.fileExists(atPath: legacyURL.path) { return readSnapshot(at: legacyURL) }
    }
    return .missing
  }

  private func readSnapshot(at url: URL) -> SnapshotReadResult {
    do {
      let data = try Data(contentsOf: url)
      let envelope = try decoder.decode(SnapshotVersionEnvelope.self, from: data)
      guard envelope.schemaVersion == WatchioSnapshot.currentSchemaVersion else {
        return .updateRequired(foundVersion: envelope.schemaVersion)
      }
      return .snapshot(try decoder.decode(WatchioSnapshot.self, from: data))
    } catch { return .corrupt }
  }

  public func save(_ snapshot: WatchioSnapshot) async throws {
    guard snapshot.isCompatible else {
      throw SnapshotStoreError.unsupportedSchema(snapshot.schemaVersion)
    }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(WatchioSharedContainer.snapshotFilename)
    let data = try encoder.encode(snapshot)
    try data.write(to: url, options: .atomic)
    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    for filename in WatchioSharedContainer.legacySnapshotFilenames {
      try? fileManager.removeItem(at: directory.appendingPathComponent(filename))
    }
  }
}

public enum SnapshotStoreError: Error, LocalizedError, Sendable {
  case unsupportedSchema(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchema(let version): "Unsupported snapshot schema \(version)"
    }
  }
}

private struct SnapshotVersionEnvelope: Decodable {
  let schemaVersion: Int
}

public final class DetectionPreferencesStore: @unchecked Sendable {
  private let defaults: UserDefaults
  private let key = "watchio.detection-preferences.v1"
  private let lock = NSLock()
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public convenience init?(appGroupIdentifier: String) {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return nil }
    self.init(defaults: defaults)
  }

  public func load() -> DetectionPreferences {
    lock.lock()
    defer { lock.unlock() }
    guard let data = defaults.data(forKey: key),
      let preferences = try? decoder.decode(DetectionPreferences.self, from: data)
    else { return Self.defaultPreferences() }
    return preferences
  }

  public func save(_ preferences: DetectionPreferences) throws {
    lock.lock()
    defer { lock.unlock() }
    defaults.set(try encoder.encode(preferences), forKey: key)
  }

  public static func defaultPreferences(
    fileManager: FileManager = .default,
    homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> DetectionPreferences {
    let candidates = ["Code", "Developer", "Projects"].map {
      homeURL.appendingPathComponent($0).path
    }
    let existing = candidates.filter { path in
      var isDirectory: ObjCBool = false
      return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        && isDirectory.boolValue
    }
    return DetectionPreferences(projectRoots: existing)
  }
}
