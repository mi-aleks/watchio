import Foundation
import XCTest

@testable import WatchioDetection
@testable import WatchioModels

private func process(
  pid: Int32 = 100,
  ppid: Int32 = 10,
  pgid: Int32 = 100,
  tty: String? = "ttys001",
  elapsed: TimeInterval = 20,
  path: String
) -> ProcessRecord {
  ProcessRecord(
    uid: 501, pid: pid, parentPID: ppid, processGroupID: pgid, tty: tty,
    elapsedSeconds: elapsed, cpuPercent: 1.5, memoryBytes: 10_000, executablePath: path
  )
}

private let project = ProjectContext(
  rootPath: "/Users/demo/Code/watchio", displayPath: "~/Code/watchio", name: "watchio",
  marker: "package.json"
)

final class ClassifierAndEngineTests: XCTestCase {
  func testSuppressesGUIHelpersAndDaemons() {
    for path in [
      "/Applications/Visual Studio Code.app/Contents/MacOS/Electron",
      "/Applications/Raycast.app/Contents/MacOS/Raycast",
      "/Applications/Docker.app/Contents/MacOS/com.docker.backend",
      "/System/Library/CoreServices/coreservicesd",
    ] {
      let result = ProcessClassifier.classify(
        process: process(tty: nil, path: path), project: nil, hasListener: true,
        hasDevelopmentAncestry: false, preferences: .init()
      )
      XCTAssertLessThan(result.confidence, 40)
    }
  }

  func testClassifiesSupportedDevelopmentRuntimes() {
    let preferences = DetectionPreferences()
    for (path, expected) in [
      ("/Users/demo/.nvm/bin/node", RuntimeKind.node),
      ("/opt/homebrew/bin/bun", .bun),
      ("/opt/homebrew/bin/deno", .deno),
      ("/private/var/tmp/go-build123/exe/api", .go),
      ("/Users/demo/.pyenv/shims/python3.12", .python),
    ] {
      let candidate = process(path: path)
      XCTAssertEqual(ProcessClassifier.runtime(for: candidate), expected)
      let result = ProcessClassifier.classify(
        process: candidate, project: project, hasListener: true,
        hasDevelopmentAncestry: true, preferences: preferences
      )
      XCTAssertGreaterThanOrEqual(result.confidence, 60)
    }
  }

  func testRuntimeToggleFullySuppressesThatRuntime() {
    var preferences = DetectionPreferences()
    preferences.enabledRuntimes.remove(.node)
    let result = ProcessClassifier.classify(
      process: process(path: "/Users/demo/.nvm/bin/node"), project: project, hasListener: true,
      hasDevelopmentAncestry: true, preferences: preferences
    )

    XCTAssertTrue(result.isIgnored)
  }

  func testClassifiesKnownAIProcessesWithoutMatchingGUIHelpers() {
    let vscode = process(
      pid: 10, ppid: 1, pgid: 10, tty: nil,
      path: "/Applications/Visual Studio Code.app/Contents/MacOS/Code Helper (Plugin)")
    let claude = process(
      pid: 11, ppid: 10, pgid: 10, tty: nil,
      path: "/Users/demo/.vscode/extensions/anthropic.claude-code-2/resources/claude")
    let records = [vscode.pid: vscode, claude.pid: claude]

    let classification = AIProcessClassifier.classify(
      process: claude, project: project, processByPID: records)

    XCTAssertEqual(classification?.tool, .claude)
    XCTAssertEqual(classification?.host, .visualStudioCode)
    XCTAssertGreaterThanOrEqual(classification?.confidence ?? 0, 60)
    XCTAssertTrue(classification?.evidence.contains(.ideHost) == true)
    for path in [
      "/Applications/ChatGPT.app/Contents/Frameworks/Codex (Renderer).app/Contents/MacOS/Codex (Renderer)",
      "/Applications/ChatGPT.app/Contents/Resources/codex-code-mode-host",
      "/System/Library/CoreServices/CursorUIViewService",
    ] {
      XCTAssertNil(AIProcessClassifier.tool(for: process(tty: nil, path: path)))
    }
  }

  func testMapsEverySupportedAIExecutableExactly() {
    let expected: [(String, AIToolKind)] = [
      ("/trusted/codex", .codex),
      ("/trusted/claude", .claude),
      ("/trusted/gemini", .gemini),
      ("/trusted/aider", .aider),
      ("/trusted/aider-chat", .aider),
      ("/trusted/opencode", .openCode),
      ("/trusted/goose", .goose),
      ("/trusted/copilot", .copilot),
      ("/trusted/github-copilot", .copilot),
      ("/trusted/cursor-agent", .cursor),
    ]

    for (path, tool) in expected {
      XCTAssertEqual(AIProcessClassifier.tool(for: process(path: path)), tool, path)
    }
    for path in ["/trusted/node", "/trusted/python3", "/trusted/codex-helper"] {
      XCTAssertNil(AIProcessClassifier.tool(for: process(path: path)), path)
    }
  }

  func testSeparatelyExecutableAIChildBecomesSubagent() async {
    let parent = process(
      pid: 600, ppid: 10, pgid: 600, path: "/Users/demo/.local/bin/claude")
    let child = process(
      pid: 601, ppid: 600, pgid: 600, path: "/Users/demo/.local/bin/claude")
    let helper = process(pid: 602, ppid: 601, pgid: 600, path: "/usr/local/bin/helper")
    let engine = DetectionEngine(
      processProvider: ProcessFixture([parent, child, helper]),
      listenerProvider: ListenerFixture([]), containerProvider: ContainerFixture([]),
      projectResolver: ProjectFixture([600: project, 601: project]), currentUID: 501
    )

    let result = await engine.scan(preferences: .init(projectRoots: ["/Users/demo/Code"]))

    XCTAssertEqual(result.aiActivities.count, 2)
    XCTAssertEqual(result.aiActivities.first { $0.representativePID == 600 }?.host, .terminal)
    XCTAssertEqual(result.aiActivities.first { $0.representativePID == 600 }?.processCount, 1)
    XCTAssertEqual(result.aiActivities.first { $0.representativePID == 601 }?.host, .subagent)
    XCTAssertEqual(result.aiActivities.first { $0.representativePID == 601 }?.processCount, 2)
  }

  func testEngineGroupsAIHelpersUnderToolRoots() async {
    let vscode = process(
      pid: 10, ppid: 1, pgid: 10, tty: nil,
      path: "/Applications/Visual Studio Code.app/Contents/MacOS/Code Helper (Plugin)")
    let codex = process(
      pid: 100, ppid: 10, pgid: 10, tty: nil,
      path: "/Users/demo/.vscode/extensions/openai.chatgpt-1/bin/codex")
    let codexHelper = process(
      pid: 101, ppid: 100, pgid: 101, tty: nil,
      path: "/Applications/ChatGPT.app/Contents/Resources/codex-code-mode-host")
    let claude = process(
      pid: 200, ppid: 10, pgid: 10, tty: nil,
      path: "/Users/demo/.vscode/extensions/anthropic.claude-code-2/resources/claude")
    let claudeHelper = process(
      pid: 201, ppid: 200, pgid: 201, tty: nil, path: "/usr/local/bin/helper")
    let untrustedCodex = process(
      pid: 300, ppid: 1, pgid: 300, tty: nil, path: "/private/tmp/codex")
    let engine = DetectionEngine(
      processProvider: ProcessFixture([
        vscode, codex, codexHelper, claude, claudeHelper, untrustedCodex,
      ]),
      listenerProvider: ListenerFixture([]), containerProvider: ContainerFixture([]),
      projectResolver: ProjectFixture([200: project]), currentUID: 501,
      now: { Date(timeIntervalSince1970: 10_000) }
    )

    let result = await engine.scan(
      preferences: DetectionPreferences(projectRoots: ["/Users/demo/Code"]))

    XCTAssertEqual(result.aiActivities.map(\.tool), [.claude, .codex])
    XCTAssertEqual(result.aiActivities.map(\.processCount), [2, 2])
    XCTAssertEqual(result.aiActivities.map(\.cpuPercent), [3, 3])
    XCTAssertEqual(result.aiActivities.map(\.memoryBytes), [20_000, 20_000])
    XCTAssertEqual(result.aiActivities.first?.projectName, "watchio")
    XCTAssertEqual(result.aiActivities.last?.host, .visualStudioCode)
  }

  func testAIActivityCanBeDisabled() async {
    let claude = process(pid: 500, path: "/Users/demo/.local/bin/claude")
    var preferences = DetectionPreferences(projectRoots: ["/Users/demo/Code"])
    preferences.observeAIActivity = false
    let engine = DetectionEngine(
      processProvider: ProcessFixture([claude]), listenerProvider: ListenerFixture([]),
      containerProvider: ContainerFixture([]), projectResolver: ProjectFixture([500: project]),
      currentUID: 501
    )

    let result = await engine.scan(preferences: preferences)

    XCTAssertTrue(result.aiActivities.isEmpty)
  }

  func testEngineGroupsChildrenAggregatesPortsAndQueuesSuggestions() async throws {
    let records = [
      process(pid: 100, ppid: 10, pgid: 100, path: "/Users/demo/.nvm/bin/node"),
      process(pid: 101, ppid: 100, pgid: 100, path: "/usr/bin/helper"),
      process(pid: 200, ppid: 10, pgid: 200, path: "/Users/demo/.pyenv/shims/python3.12"),
      process(pid: 300, ppid: 10, pgid: 300, elapsed: 2, path: "/opt/homebrew/bin/bun"),
    ]
    let engine = DetectionEngine(
      processProvider: ProcessFixture(records),
      listenerProvider: ListenerFixture([
        PortRecord(pid: 101, endpoint: .init(transport: .tcp, address: "127.0.0.1", port: 3000))
      ]),
      containerProvider: ContainerFixture([]),
      projectResolver: ProjectFixture([100: project, 101: project]),
      currentUID: 501,
      now: { Date(timeIntervalSince1970: 10_000) }
    )
    let result = await engine.scan(
      preferences: DetectionPreferences(projectRoots: ["/Users/demo/Code"]))

    XCTAssertEqual(result.services.count, 1)
    XCTAssertEqual(result.services[0].runtime, .node)
    XCTAssertEqual(result.services[0].processCount, 2)
    XCTAssertEqual(result.services[0].ports.map(\.port), [3000])
    XCTAssertEqual(result.reviewSuggestions.count, 1)
    XCTAssertEqual(result.reviewSuggestions[0].service.runtime, .python)
    XCTAssertFalse(result.services.contains { $0.runtime == .bun })
  }

  func testEngineAddsComposeContainersWithoutDockerBackendRows() async {
    let container = ContainerRecord(
      id: "abc", name: "postgres", projectName: "watchio", projectPath: "~/Code/watchio",
      ports: [.init(transport: .tcp, address: "0.0.0.0", port: 5432)], startedAt: nil
    )
    let engine = DetectionEngine(
      processProvider: ProcessFixture([]), listenerProvider: ListenerFixture([]),
      containerProvider: ContainerFixture([container]), projectResolver: ProjectFixture([:]),
      currentUID: 501
    )
    let result = await engine.scan(preferences: .init())
    XCTAssertEqual(result.services.count, 1)
    XCTAssertEqual(result.services[0].runtime, .docker)
    XCTAssertEqual(result.services[0].name, "postgres")
  }

  func testEngineQueriesUDPOnlyForQualifiedServiceGroups() async {
    let listener = RecordingListenerFixture(
      udp: [
        PortRecord(pid: 101, endpoint: .init(transport: .udp, address: "127.0.0.1", port: 5353)),
        PortRecord(pid: 999, endpoint: .init(transport: .udp, address: "*", port: 9999)),
      ])
    let records = [
      process(pid: 100, ppid: 10, pgid: 100, path: "/Users/demo/.nvm/bin/node"),
      process(pid: 101, ppid: 100, pgid: 100, path: "/usr/bin/helper"),
      process(pid: 999, ppid: 1, pgid: 999, tty: nil, path: "/usr/bin/unrelated"),
    ]
    let engine = DetectionEngine(
      processProvider: ProcessFixture(records), listenerProvider: listener,
      containerProvider: ContainerFixture([]),
      projectResolver: ProjectFixture([100: project, 101: project]), currentUID: 501
    )

    let result = await engine.scan(
      preferences: DetectionPreferences(projectRoots: ["/Users/demo/Code"]))

    let requestedProcessIDs = await listener.requestedProcessIDs
    XCTAssertEqual(requestedProcessIDs, [100, 101])
    XCTAssertEqual(result.services.first?.ports.map(\.port), [5353])
  }

  func testInventoryPermissionFailuresProduceSafeDegradedHealth() async {
    let engine = DetectionEngine(
      processProvider: FailingProcessFixture(), listenerProvider: FailingListenerFixture(),
      containerProvider: ContainerFixture([]), projectResolver: ProjectFixture([:]), currentUID: 501
    )

    let result = await engine.scan(preferences: .init())

    XCTAssertTrue(result.services.isEmpty)
    XCTAssertEqual(result.sourceHealth.first { $0.source == .processes }?.state, .unavailable)
    XCTAssertEqual(result.sourceHealth.first { $0.source == .listeners }?.state, .unavailable)
    XCTAssertFalse(result.sourceHealth.compactMap(\.message).contains { $0.contains("Users") })
  }

  func testPIDReuseDoesNotCarryPreviousListenerState() async {
    let reusedProcess = process(pid: 410, ppid: 10, pgid: 410, path: "/Users/demo/.nvm/bin/node")
    let firstEngine = DetectionEngine(
      processProvider: ProcessFixture([reusedProcess]),
      listenerProvider: ListenerFixture([
        PortRecord(pid: 410, endpoint: .init(transport: .tcp, address: "127.0.0.1", port: 3000))
      ]), containerProvider: ContainerFixture([]), projectResolver: ProjectFixture([410: project]),
      currentUID: 501
    )
    let secondEngine = DetectionEngine(
      processProvider: ProcessFixture([reusedProcess]),
      listenerProvider: ListenerFixture([
        PortRecord(pid: 410, endpoint: .init(transport: .tcp, address: "127.0.0.1", port: 4000))
      ]), containerProvider: ContainerFixture([]), projectResolver: ProjectFixture([410: project]),
      currentUID: 501
    )

    let first = await firstEngine.scan(preferences: .init())
    let second = await secondEngine.scan(preferences: .init())

    XCTAssertEqual(first.services.first?.id, second.services.first?.id)
    XCTAssertEqual(first.services.first?.ports.map(\.port), [3000])
    XCTAssertEqual(second.services.first?.ports.map(\.port), [4000])
  }
}

private struct ProcessFixture: ProcessInventoryProviding {
  let value: [ProcessRecord]
  init(_ value: [ProcessRecord]) { self.value = value }
  func processes() async throws -> [ProcessRecord] { value }
}

private struct FailingProcessFixture: ProcessInventoryProviding {
  func processes() async throws -> [ProcessRecord] {
    throw InventoryError.commandFailed("ps", 1, "/Users/demo/private-detail")
  }
}

private struct ListenerFixture: ListenerInventoryProviding {
  let value: [PortRecord]
  init(_ value: [PortRecord]) { self.value = value }
  func tcpListeners() async throws -> [PortRecord] {
    value.filter { $0.endpoint.transport == .tcp }
  }
  func udpBindings(for processIDs: [Int32]) async throws -> [PortRecord] {
    value.filter { processIDs.contains($0.pid) && $0.endpoint.transport == .udp }
  }
}

private actor RecordingListenerFixture: ListenerInventoryProviding {
  private let tcp: [PortRecord]
  private let udp: [PortRecord]
  private(set) var requestedProcessIDs: [Int32] = []

  init(tcp: [PortRecord] = [], udp: [PortRecord]) {
    self.tcp = tcp
    self.udp = udp
  }

  func tcpListeners() async throws -> [PortRecord] { tcp }

  func udpBindings(for processIDs: [Int32]) async throws -> [PortRecord] {
    requestedProcessIDs = processIDs.sorted()
    return udp.filter { processIDs.contains($0.pid) }
  }
}

private struct FailingListenerFixture: ListenerInventoryProviding {
  func tcpListeners() async throws -> [PortRecord] {
    throw InventoryError.commandFailed("lsof", 1, "/Users/demo/private-detail")
  }

  func udpBindings(for processIDs: [Int32]) async throws -> [PortRecord] { [] }
}

private struct ContainerFixture: ContainerInventoryProviding {
  let value: [ContainerRecord]
  init(_ value: [ContainerRecord]) { self.value = value }
  func containers() async throws -> [ContainerRecord] { value }
}

private struct ProjectFixture: ProjectResolving {
  let value: [Int32: ProjectContext]
  init(_ value: [Int32: ProjectContext]) { self.value = value }
  func projects(for processes: [ProcessRecord], roots: [String]) async throws -> [Int32:
    ProjectContext]
  { value }
}
