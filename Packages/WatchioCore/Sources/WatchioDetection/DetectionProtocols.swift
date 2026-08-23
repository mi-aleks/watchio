import Foundation
import WatchioModels

public protocol ProcessInventoryProviding: Sendable {
  func processes() async throws -> [ProcessRecord]
}

public protocol ListenerInventoryProviding: Sendable {
  func tcpListeners() async throws -> [PortRecord]
  func udpBindings(for processIDs: [Int32]) async throws -> [PortRecord]
}

public protocol ContainerInventoryProviding: Sendable {
  func containers() async throws -> [ContainerRecord]
}

public protocol ProjectResolving: Sendable {
  func projects(for processes: [ProcessRecord], roots: [String]) async throws -> [Int32:
    ProjectContext]
}

public struct CommandResult: Sendable {
  public let standardOutput: Data
  public let standardError: Data
  public let exitCode: Int32

  public init(standardOutput: Data, standardError: Data, exitCode: Int32) {
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.exitCode = exitCode
  }

  public var outputString: String { String(decoding: standardOutput, as: UTF8.self) }
  public var errorString: String { String(decoding: standardError, as: UTF8.self) }
}

public protocol CommandRunning: Sendable {
  func run(executable: URL, arguments: [String], timeout: Duration) async throws -> CommandResult
}

public enum InventoryError: Error, LocalizedError, Sendable {
  case commandTimedOut(String)
  case commandFailed(String, Int32, String)
  case outputLimitExceeded(String)
  case malformedOutput(String)
  case unavailable(String)

  public var errorDescription: String? {
    switch self {
    case .commandTimedOut(let command): "\(command) timed out"
    case .commandFailed(let command, let code, let message):
      "\(command) exited with \(code): \(message)"
    case .outputLimitExceeded(let command): "\(command) exceeded the output limit"
    case .malformedOutput(let source): "Could not parse \(source) output"
    case .unavailable(let source): "\(source) is unavailable"
    }
  }
}
