import Foundation
import WatchioModels

public struct AIProcessClassification: Hashable, Sendable {
  public let tool: AIToolKind
  public let host: AIActivityHost
  public let confidence: Int
  public let evidence: [AIActivityEvidence]

  public init(
    tool: AIToolKind, host: AIActivityHost, confidence: Int,
    evidence: [AIActivityEvidence]
  ) {
    self.tool = tool
    self.host = host
    self.confidence = confidence
    self.evidence = evidence
  }
}

public enum AIProcessClassifier {
  private static let visualStudioCodeFragments = [
    "/Visual Studio Code.app/", "/.vscode/extensions/",
  ]
  private static let desktopFragments = [
    "/ChatGPT.app/", "/Claude.app/",
  ]
  private static let trustedBinFragments = [
    "/.local/bin/", "/opt/homebrew/bin/", "/usr/local/bin/",
  ]

  public static func tool(for process: ProcessRecord) -> AIToolKind? {
    switch process.executableName.lowercased() {
    case "codex": .codex
    case "claude": .claude
    case "gemini": .gemini
    case "aider", "aider-chat": .aider
    case "opencode": .openCode
    case "goose": .goose
    case "copilot", "github-copilot": .copilot
    case "cursor-agent": .cursor
    default: nil
    }
  }

  public static func classify(
    process: ProcessRecord, project: ProjectContext?, processByPID: [Int32: ProcessRecord]
  ) -> AIProcessClassification? {
    guard let selectedTool = tool(for: process) else { return nil }
    let ancestors = ancestorChain(for: process, processByPID: processByPID)
    let hasAIAncestor = ancestors.contains { tool(for: $0) != nil }
    let inVisualStudioCode = ([process] + ancestors).contains {
      visualStudioCodeFragments.contains(where: $0.executablePath.contains)
    }
    let inDesktopHost = ([process] + ancestors).contains {
      desktopFragments.contains(where: $0.executablePath.contains)
    }
    let host: AIActivityHost
    if hasAIAncestor {
      host = .subagent
    } else if process.tty != nil {
      host = .terminal
    } else if inVisualStudioCode {
      host = .visualStudioCode
    } else if inDesktopHost {
      host = .desktop
    } else {
      host = .background
    }

    var confidence = 45
    var evidence: [AIActivityEvidence] = [.knownExecutable]
    if isTrustedInstall(process: process, tool: selectedTool) {
      confidence += 20
      evidence.append(.trustedInstallPath)
    }
    if project != nil {
      confidence += 15
      evidence.append(.projectWorkingDirectory)
    }
    if process.tty != nil {
      confidence += 15
      evidence.append(.terminalSession)
    }
    if inVisualStudioCode {
      confidence += 15
      evidence.append(.ideHost)
    }
    if inDesktopHost {
      confidence += 15
      evidence.append(.desktopHost)
    }
    if hasAIAncestor {
      confidence += 10
      evidence.append(.agentAncestry)
    }

    return AIProcessClassification(
      tool: selectedTool,
      host: host,
      confidence: min(100, confidence),
      evidence: Array(Set(evidence)).sorted { $0.rawValue < $1.rawValue }
    )
  }

  private static func isTrustedInstall(process: ProcessRecord, tool: AIToolKind) -> Bool {
    let path = process.executablePath
    if trustedBinFragments.contains(where: path.contains) { return true }
    switch tool {
    case .codex:
      return path.contains("/.codex/") || path.contains("/openai.chatgpt-")
        || path.contains("/ChatGPT.app/Contents/Resources/codex")
    case .claude:
      return path.contains("/.claude/") || path.contains("/anthropic.claude-code-")
        || path.contains("/Claude.app/")
    case .gemini:
      return path.contains("/@google/gemini-cli/") || path.contains("/.gemini/")
    case .aider:
      return path.contains("/aider-chat/") || path.contains("/site-packages/aider/")
    case .openCode:
      return path.contains("/.opencode/") || path.contains("/opencode-ai/")
    case .goose:
      return path.contains("/.config/goose/") || path.contains("/block-goose/")
    case .copilot:
      return path.contains("/@github/copilot/") || path.contains("/github.copilot-")
    case .cursor:
      return path.contains("/Cursor.app/") || path.contains("/.cursor/")
    }
  }

  private static func ancestorChain(
    for process: ProcessRecord, processByPID: [Int32: ProcessRecord], maximumDepth: Int = 24
  ) -> [ProcessRecord] {
    var result: [ProcessRecord] = []
    var parentPID = process.parentPID
    var visited: Set<Int32> = [process.pid]
    for _ in 0..<maximumDepth {
      guard let parent = processByPID[parentPID], visited.insert(parent.pid).inserted else { break }
      result.append(parent)
      parentPID = parent.parentPID
    }
    return result
  }
}
