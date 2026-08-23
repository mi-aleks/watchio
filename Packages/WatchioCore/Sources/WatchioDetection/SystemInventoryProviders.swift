import Foundation
import WatchioModels

public struct PSProcessInventoryProvider: ProcessInventoryProviding {
  private let runner: any CommandRunning

  public init(runner: any CommandRunning = ProcessCommandRunner()) {
    self.runner = runner
  }

  public func processes() async throws -> [ProcessRecord] {
    let result = try await runner.run(
      executable: URL(fileURLWithPath: "/bin/ps"),
      arguments: ["-axo", "uid=,pid=,ppid=,pgid=,tty=,etime=,%cpu=,rss=,comm="],
      timeout: .seconds(4)
    )
    guard result.exitCode == 0 else {
      throw InventoryError.commandFailed("ps", result.exitCode, result.errorString)
    }
    return PSInventoryParser.parse(result.outputString)
  }
}

public struct LsofListenerInventoryProvider: ListenerInventoryProviding {
  private let runner: any CommandRunning
  private let username: String

  public init(runner: any CommandRunning = ProcessCommandRunner(), username: String = NSUserName())
  {
    self.runner = runner
    self.username = username
  }

  public func tcpListeners() async throws -> [PortRecord] {
    try await query(
      arguments: ["-nP", "-a", "-u", username, "-iTCP", "-sTCP:LISTEN", "-FpcnT"],
      transport: .tcp
    )
  }

  public func udpBindings(for processIDs: [Int32]) async throws -> [PortRecord] {
    let uniqueProcessIDs = Array(Set(processIDs)).sorted()
    guard !uniqueProcessIDs.isEmpty else { return [] }

    var bindings: [PortRecord] = []
    for batch in uniqueProcessIDs.chunked(maxCount: 64) {
      bindings.append(
        contentsOf: try await query(
          arguments: [
            "-nP", "-a", "-p", batch.map(String.init).joined(separator: ","), "-iUDP", "-Fpcn",
          ],
          transport: .udp
        ))
    }
    return Array(Set(bindings)).sorted(by: Self.sortPorts)
  }

  private func query(arguments: [String], transport: NetworkTransport) async throws -> [PortRecord]
  {
    let result = try await runner.run(
      executable: URL(fileURLWithPath: "/usr/sbin/lsof"), arguments: arguments, timeout: .seconds(5)
    )
    // lsof uses status 1 when a valid query has no matches.
    guard result.exitCode == 0 || (result.exitCode == 1 && result.standardOutput.isEmpty) else {
      throw InventoryError.commandFailed("lsof", result.exitCode, result.errorString)
    }
    return Array(Set(LsofInventoryParser.parseListeners(result.outputString, transport: transport)))
      .sorted(by: Self.sortPorts)
  }

  private static func sortPorts(_ lhs: PortRecord, _ rhs: PortRecord) -> Bool {
    if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
    if lhs.endpoint.port != rhs.endpoint.port { return lhs.endpoint.port < rhs.endpoint.port }
    return lhs.endpoint.transport.rawValue < rhs.endpoint.transport.rawValue
  }
}

public struct LsofProjectResolver: ProjectResolving, @unchecked Sendable {
  private static let markers = [
    ".git", "package.json", "go.mod", "pyproject.toml", "uv.lock", "Pipfile", "Package.swift",
    "Cargo.toml",
  ]
  private let runner: any CommandRunning
  private let fileManager: FileManager
  private let homePath: String

  public init(
    runner: any CommandRunning = ProcessCommandRunner(), fileManager: FileManager = .default,
    homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
  ) {
    self.runner = runner
    self.fileManager = fileManager
    self.homePath = homePath
  }

  public func projects(for processes: [ProcessRecord], roots: [String]) async throws -> [Int32:
    ProjectContext]
  {
    let normalizedRoots = roots.map(expandPath).map(URL.init(fileURLWithPath:)).map(
      standardizedPath)
    guard !normalizedRoots.isEmpty, !processes.isEmpty else { return [:] }

    var workingDirectories: [Int32: String] = [:]
    let processIDs = processes.map(\.pid)
    for batch in processIDs.chunked(maxCount: 64) {
      let result = try await runner.run(
        executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
        arguments: [
          "-nP", "-a", "-d", "cwd", "-p", batch.map(String.init).joined(separator: ","), "-Fpcn",
        ],
        timeout: .seconds(5)
      )
      guard result.exitCode == 0 || result.exitCode == 1 else {
        throw InventoryError.commandFailed("lsof", result.exitCode, result.errorString)
      }
      workingDirectories.merge(LsofInventoryParser.parseWorkingDirectories(result.outputString)) {
        _, new in new
      }
    }

    var cache: [String: ProjectContext?] = [:]
    return workingDirectories.reduce(into: [:]) { result, entry in
      let cwd = standardizedPath(URL(fileURLWithPath: entry.value))
      guard normalizedRoots.contains(where: { isDescendant(cwd, of: $0) }) else { return }
      let context: ProjectContext?
      if let cached = cache[cwd] {
        context = cached
      } else {
        context = resolveProject(startingAt: cwd, roots: normalizedRoots)
        cache[cwd] = context
      }
      if let context { result[entry.key] = context }
    }
  }

  private func resolveProject(startingAt path: String, roots: [String]) -> ProjectContext? {
    var current = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    while roots.contains(where: { isDescendant(current.path, of: $0) }) {
      for marker in Self.markers
      where fileManager.fileExists(atPath: current.appendingPathComponent(marker).path) {
        return ProjectContext(
          rootPath: current.path,
          displayPath: displayPath(current.path),
          name: current.lastPathComponent,
          marker: marker
        )
      }
      let parent = current.deletingLastPathComponent()
      if parent.path == current.path { break }
      current = parent
    }
    return nil
  }

  private func expandPath(_ path: String) -> String {
    if path == "~" { return homePath }
    if path.hasPrefix("~/") { return homePath + path.dropFirst() }
    return (path as NSString).expandingTildeInPath
  }

  private func displayPath(_ path: String) -> String {
    guard path == homePath || path.hasPrefix(homePath + "/") else {
      return URL(fileURLWithPath: path).lastPathComponent
    }
    return "~" + path.dropFirst(homePath.count)
  }

  private func standardizedPath(_ url: URL) -> String { url.standardizedFileURL.path }

  private func isDescendant(_ path: String, of root: String) -> Bool {
    path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
  }
}

extension Array {
  fileprivate func chunked(maxCount: Int) -> [[Element]] {
    guard maxCount > 0 else { return [] }
    return stride(from: 0, to: count, by: maxCount).map {
      Array(self[$0..<Swift.min($0 + maxCount, count)])
    }
  }
}
