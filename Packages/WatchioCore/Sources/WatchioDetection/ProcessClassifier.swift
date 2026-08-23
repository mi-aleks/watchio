import Darwin
import Foundation
import WatchioModels

public struct Classification: Hashable, Sendable {
  public let runtime: RuntimeKind
  public let confidence: Int
  public let evidence: [ConfidenceEvidence]
  public let isIgnored: Bool

  public init(
    runtime: RuntimeKind, confidence: Int, evidence: [ConfidenceEvidence], isIgnored: Bool
  ) {
    self.runtime = runtime
    self.confidence = confidence
    self.evidence = evidence
    self.isIgnored = isIgnored
  }
}

public enum ProcessClassifier {
  private static let shells = ["bash", "zsh", "fish", "nu", "xonsh"]
  private static let terminalAndIDEFragments = [
    "/Terminal.app/", "/iTerm.app/", "/Warp.app/", "/Visual Studio Code.app/", "/Cursor.app/",
    "/Zed.app/", "/Xcode.app/",
  ]
  private static let guiAndDaemonFragments = [
    "/System/Library/", "/usr/libexec/", "/Applications/", ".app/Contents/MacOS/", "Watchio",
    "com.apple.", "Docker Desktop.app/Contents/MacOS/com.docker.backend",
  ]
  private static let toolchainFragments = [
    "/.nvm/", "/.asdf/", "/.volta/", "/.pyenv/", "/.local/bin/", "/go/bin/", "/Cellar/",
    "/opt/homebrew/", "/go-build",
  ]

  public static func runtime(for process: ProcessRecord) -> RuntimeKind? {
    let name = process.executableName.lowercased()
    let path = process.executablePath.lowercased()
    if name == "node" || name.hasPrefix("node-") { return .node }
    if name == "bun" || name == "bunx" { return .bun }
    if name == "deno" { return .deno }
    if name == "go" || path.contains("/go-build") { return .go }
    if name == "python" || name.hasPrefix("python3") || name.hasPrefix("python2") { return .python }
    return nil
  }

  public static func classify(
    process: ProcessRecord,
    project: ProjectContext?,
    hasListener: Bool,
    hasDevelopmentAncestry: Bool,
    preferences: DetectionPreferences
  ) -> Classification {
    let runtime = runtime(for: process) ?? .generic
    var score = 0
    var evidence: [ConfidenceEvidence] = []

    if project != nil {
      score += 40
      evidence.append(.projectRoot)
    }
    if runtime != .generic, preferences.enabledRuntimes.contains(runtime) {
      score += 25
      evidence.append(.supportedRuntime)
    }
    if hasListener {
      score += 20
      evidence.append(.listeningEndpoint)
    }
    if hasDevelopmentAncestry || process.tty != nil {
      score += 15
      evidence.append(.developmentAncestry)
    }
    if toolchainFragments.contains(where: process.executablePath.contains) {
      score += 10
      evidence.append(.toolchainPath)
    }

    let searchable = [process.executablePath, project?.rootPath, project?.name].compactMap { $0 }
      .joined(separator: " ")
    if preferences.includeRules.contains(where: { glob($0, matches: searchable) }) {
      score += 100
      evidence.append(.includeRule)
    }
    let ignored = preferences.ignoreRules.contains(where: { glob($0, matches: searchable) })
    let runtimeDisabled = runtime != .generic && !preferences.enabledRuntimes.contains(runtime)

    if guiAndDaemonFragments.contains(where: process.executablePath.contains) {
      score -= project == nil ? 100 : 35
    }
    if process.parentPID == 1, project == nil { score -= 50 }
    if runtime == .generic, project == nil { score -= 30 }

    return Classification(
      runtime: runtime,
      confidence: max(0, min(100, score)),
      evidence: Array(Set(evidence)).sorted { $0.rawValue < $1.rawValue },
      isIgnored: ignored || runtimeDisabled
    )
  }

  public static func hasDevelopmentAncestry(
    process: ProcessRecord, processByPID: [Int32: ProcessRecord], maximumDepth: Int = 12
  ) -> Bool {
    var current = process
    var visited: Set<Int32> = []
    for _ in 0..<maximumDepth {
      guard visited.insert(current.pid).inserted else { break }
      if shells.contains(current.executableName.lowercased())
        || terminalAndIDEFragments.contains(where: current.executablePath.contains)
      {
        return true
      }
      guard let parent = processByPID[current.parentPID] else { break }
      current = parent
    }
    return false
  }

  private static func glob(_ pattern: String, matches value: String) -> Bool {
    fnmatch(pattern, value, FNM_CASEFOLD) == 0
  }
}
