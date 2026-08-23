import Foundation

public enum RuntimeKind: String, Codable, CaseIterable, Hashable, Sendable {
  case node, bun, deno, go, python, docker, generic

  public var displayName: String {
    switch self {
    case .node: "Node.js"
    case .bun: "Bun"
    case .deno: "Deno"
    case .go: "Go"
    case .python: "Python"
    case .docker: "Docker"
    case .generic: "Process"
    }
  }
}

public enum NetworkTransport: String, Codable, Hashable, Sendable { case tcp, udp }

public struct ListeningEndpoint: Codable, Hashable, Identifiable, Sendable {
  public let transport: NetworkTransport
  public let address: String
  public let port: Int

  public init(transport: NetworkTransport, address: String, port: Int) {
    self.transport = transport
    self.address = address
    self.port = port
  }

  public var id: String { "\(transport.rawValue):\(address):\(port)" }
  public var isLoopback: Bool {
    address == "127.0.0.1" || address == "::1" || address == "localhost"
  }
  public var displayValue: String { ":\(port)" }
}

public enum ConfidenceEvidence: String, Codable, CaseIterable, Hashable, Sendable {
  case projectRoot, supportedRuntime, listeningEndpoint, developmentAncestry, toolchainPath,
    includeRule, dockerMetadata

  public var displayName: String {
    switch self {
    case .projectRoot: "Project working directory"
    case .supportedRuntime: "Known development runtime"
    case .listeningEndpoint: "Listening on a local port"
    case .developmentAncestry: "Launched from a terminal or IDE"
    case .toolchainPath: "Installed by a development toolchain"
    case .includeRule: "Included by your rule"
    case .dockerMetadata: "Docker Compose metadata"
    }
  }
}

public struct DetectedService: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let projectName: String
  public let projectPath: String?
  public let runtime: RuntimeKind
  public let representativePID: Int32?
  public let processCount: Int
  public let ports: [ListeningEndpoint]
  public let cpuPercent: Double?
  public let memoryBytes: UInt64?
  public let startedAt: Date?
  public let confidence: Int
  public let evidence: [ConfidenceEvidence]

  public init(
    id: String, name: String, projectName: String, projectPath: String?, runtime: RuntimeKind,
    representativePID: Int32?, processCount: Int, ports: [ListeningEndpoint], cpuPercent: Double?,
    memoryBytes: UInt64?, startedAt: Date?, confidence: Int, evidence: [ConfidenceEvidence]
  ) {
    self.id = id
    self.name = name
    self.projectName = projectName
    self.projectPath = projectPath
    self.runtime = runtime
    self.representativePID = representativePID
    self.processCount = processCount
    self.ports = ports
    self.cpuPercent = cpuPercent
    self.memoryBytes = memoryBytes
    self.startedAt = startedAt
    self.confidence = confidence
    self.evidence = evidence
  }

  public func uptime(referenceDate: Date = .now) -> TimeInterval? {
    guard let startedAt else { return nil }
    return max(0, referenceDate.timeIntervalSince(startedAt))
  }
}

public enum InventorySource: String, Codable, Hashable, Sendable {
  case processes, listeners, projects, docker
}
public enum SourceState: String, Codable, Hashable, Sendable {
  case available, degraded, unavailable
}

public struct SourceHealth: Codable, Hashable, Identifiable, Sendable {
  public let source: InventorySource
  public let state: SourceState
  public let message: String?

  public init(source: InventorySource, state: SourceState, message: String? = nil) {
    self.source = source
    self.state = state
    self.message = message
  }

  public var id: InventorySource { source }
}

public enum CollectorState: String, Codable, Hashable, Sendable {
  case active, degraded, offline, incompatible
}

public struct ReviewSuggestion: Codable, Hashable, Identifiable, Sendable {
  public let service: DetectedService
  public init(service: DetectedService) { self.service = service }
  public var id: String { service.id }
}

public struct WatchioSnapshot: Codable, Hashable, Sendable {
  public static let currentSchemaVersion = 1
  public let schemaVersion: Int
  public let generatedAt: Date
  public let collectorState: CollectorState
  public let services: [DetectedService]
  public let reviewSuggestions: [ReviewSuggestion]
  public let sourceHealth: [SourceHealth]

  public init(
    schemaVersion: Int = WatchioSnapshot.currentSchemaVersion, generatedAt: Date = .now,
    collectorState: CollectorState, services: [DetectedService],
    reviewSuggestions: [ReviewSuggestion] = [],
    sourceHealth: [SourceHealth] = []
  ) {
    self.schemaVersion = schemaVersion
    self.generatedAt = generatedAt
    self.collectorState = collectorState
    self.services = services
    self.reviewSuggestions = reviewSuggestions
    self.sourceHealth = sourceHealth
  }

  public static let empty = WatchioSnapshot(
    generatedAt: .distantPast, collectorState: .offline, services: [])
  public var isCompatible: Bool { schemaVersion == Self.currentSchemaVersion }
  public func isStale(referenceDate: Date = .now, threshold: TimeInterval = 30) -> Bool {
    referenceDate.timeIntervalSince(generatedAt) > threshold
  }
}

public struct DetectionPreferences: Codable, Hashable, Sendable {
  public var scanInterval: TimeInterval
  public var projectRoots: [String]
  public var enabledRuntimes: Set<RuntimeKind>
  public var includeRules: [String]
  public var ignoreRules: [String]
  public var showProjectPaths: Bool

  public init(
    scanInterval: TimeInterval = 10, projectRoots: [String] = [],
    enabledRuntimes: Set<RuntimeKind> = Set(RuntimeKind.allCases.filter { $0 != .generic }),
    includeRules: [String] = [], ignoreRules: [String] = [], showProjectPaths: Bool = true
  ) {
    self.scanInterval = scanInterval
    self.projectRoots = projectRoots
    self.enabledRuntimes = enabledRuntimes
    self.includeRules = includeRules
    self.ignoreRules = ignoreRules
    self.showProjectPaths = showProjectPaths
  }

  private enum CodingKeys: String, CodingKey {
    case scanInterval, projectRoots, enabledRuntimes, includeRules, ignoreRules, showProjectPaths
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    scanInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .scanInterval) ?? 10
    projectRoots = try container.decodeIfPresent([String].self, forKey: .projectRoots) ?? []
    enabledRuntimes =
      try container.decodeIfPresent(Set<RuntimeKind>.self, forKey: .enabledRuntimes)
      ?? Set(RuntimeKind.allCases.filter { $0 != .generic })
    includeRules = try container.decodeIfPresent([String].self, forKey: .includeRules) ?? []
    ignoreRules = try container.decodeIfPresent([String].self, forKey: .ignoreRules) ?? []
    showProjectPaths = try container.decodeIfPresent(Bool.self, forKey: .showProjectPaths) ?? true
  }
}

public struct ProcessRecord: Hashable, Sendable {
  public let uid: uid_t
  public let pid: Int32
  public let parentPID: Int32
  public let processGroupID: Int32
  public let tty: String?
  public let elapsedSeconds: TimeInterval
  public let cpuPercent: Double
  public let memoryBytes: UInt64
  public let executablePath: String

  public init(
    uid: uid_t, pid: Int32, parentPID: Int32, processGroupID: Int32, tty: String?,
    elapsedSeconds: TimeInterval, cpuPercent: Double, memoryBytes: UInt64, executablePath: String
  ) {
    self.uid = uid
    self.pid = pid
    self.parentPID = parentPID
    self.processGroupID = processGroupID
    self.tty = tty
    self.elapsedSeconds = elapsedSeconds
    self.cpuPercent = cpuPercent
    self.memoryBytes = memoryBytes
    self.executablePath = executablePath
  }

  public var executableName: String { URL(fileURLWithPath: executablePath).lastPathComponent }
}

public struct PortRecord: Hashable, Sendable {
  public let pid: Int32
  public let endpoint: ListeningEndpoint
  public init(pid: Int32, endpoint: ListeningEndpoint) {
    self.pid = pid
    self.endpoint = endpoint
  }
}

public struct ProjectContext: Hashable, Sendable {
  public let rootPath: String
  public let displayPath: String
  public let name: String
  public let marker: String
  public init(rootPath: String, displayPath: String, name: String, marker: String) {
    self.rootPath = rootPath
    self.displayPath = displayPath
    self.name = name
    self.marker = marker
  }
}

public struct ContainerRecord: Hashable, Sendable {
  public let id: String
  public let name: String
  public let projectName: String
  public let projectPath: String?
  public let ports: [ListeningEndpoint]
  public let startedAt: Date?
  public init(
    id: String, name: String, projectName: String, projectPath: String?, ports: [ListeningEndpoint],
    startedAt: Date?
  ) {
    self.id = id
    self.name = name
    self.projectName = projectName
    self.projectPath = projectPath
    self.ports = ports
    self.startedAt = startedAt
  }
}

public struct DetectionResult: Hashable, Sendable {
  public let services: [DetectedService]
  public let reviewSuggestions: [ReviewSuggestion]
  public let sourceHealth: [SourceHealth]
  public init(
    services: [DetectedService], reviewSuggestions: [ReviewSuggestion], sourceHealth: [SourceHealth]
  ) {
    self.services = services
    self.reviewSuggestions = reviewSuggestions
    self.sourceHealth = sourceHealth
  }
}

public enum StableIdentifier {
  public static func make(_ components: [String]) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in components.joined(separator: "\u{1F}").utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16, uppercase: false)
  }
}

public enum DemoData {
  public static let snapshot = WatchioSnapshot(
    generatedAt: .now,
    collectorState: .active,
    services: [
      DetectedService(
        id: "demo-web", name: "watchio-web", projectName: "watchio", projectPath: "~/Code/watchio",
        runtime: .node, representativePID: 48_211, processCount: 3,
        ports: [ListeningEndpoint(transport: .tcp, address: "127.0.0.1", port: 3010)],
        cpuPercent: 3.2, memoryBytes: 184 * 1_024 * 1_024,
        startedAt: .now.addingTimeInterval(-1_080),
        confidence: 100, evidence: [.projectRoot, .supportedRuntime, .listeningEndpoint]
      ),
      DetectedService(
        id: "demo-api", name: "watchio-api", projectName: "watchio-api",
        projectPath: "~/Code/watchio/api",
        runtime: .go, representativePID: 48_302, processCount: 2,
        ports: [ListeningEndpoint(transport: .tcp, address: "127.0.0.1", port: 8080)],
        cpuPercent: 1.1, memoryBytes: 42 * 1_024 * 1_024,
        startedAt: .now.addingTimeInterval(-1_080),
        confidence: 100, evidence: [.projectRoot, .supportedRuntime, .listeningEndpoint]
      ),
      DetectedService(
        id: "demo-worker", name: "events-worker", projectName: "watchio-workers",
        projectPath: "~/Code/watchio/workers",
        runtime: .bun, representativePID: 48_742, processCount: 1, ports: [], cpuPercent: 0.4,
        memoryBytes: 76 * 1_024 * 1_024, startedAt: .now.addingTimeInterval(-720), confidence: 80,
        evidence: [.projectRoot, .supportedRuntime, .developmentAncestry]
      ),
      DetectedService(
        id: "demo-db", name: "postgres", projectName: "watchio", projectPath: "~/Code/watchio",
        runtime: .docker, representativePID: nil, processCount: 1,
        ports: [ListeningEndpoint(transport: .tcp, address: "*", port: 5432)], cpuPercent: nil,
        memoryBytes: nil, startedAt: .now.addingTimeInterval(-2_520), confidence: 100,
        evidence: [.dockerMetadata, .listeningEndpoint]
      ),
    ]
  )
}
