import Darwin
import Foundation

private final class LockedOutput: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()
  private(set) var exceededLimit = false
  private let limit: Int

  init(limit: Int) { self.limit = limit }

  func append(_ newData: Data) {
    lock.lock()
    defer { lock.unlock() }
    guard !exceededLimit else { return }
    let remaining = limit - data.count
    if newData.count > remaining {
      data.append(newData.prefix(max(0, remaining)))
      exceededLimit = true
    } else {
      data.append(newData)
    }
  }

  func snapshot() -> Data {
    lock.lock()
    defer { lock.unlock() }
    return data
  }
}

private final class ProcessBox: @unchecked Sendable {
  let process: Process
  init(_ process: Process) { self.process = process }
}

public final class ProcessCommandRunner: CommandRunning, @unchecked Sendable {
  private let outputLimit: Int

  public init(outputLimit: Int = 2 * 1_024 * 1_024) {
    self.outputLimit = outputLimit
  }

  public func run(executable: URL, arguments: [String], timeout: Duration = .seconds(5))
    async throws -> CommandResult
  {
    let process = Process()
    let processBox = ProcessBox(process)
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let output = LockedOutput(limit: outputLimit)
    let errors = LockedOutput(limit: outputLimit)

    process.executableURL = executable
    process.arguments = arguments
    process.environment = [
      "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
      "LANG": "C",
      "LC_ALL": "C",
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin",
    ]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty { output.append(data) }
    }
    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty { errors.append(data) }
    }

    let termination = AsyncStream<Int32> { continuation in
      process.terminationHandler = { terminated in
        continuation.yield(terminated.terminationStatus)
        continuation.finish()
      }
    }

    do {
      try process.run()
    } catch {
      outputPipe.fileHandleForReading.readabilityHandler = nil
      errorPipe.fileHandleForReading.readabilityHandler = nil
      throw InventoryError.unavailable(executable.path)
    }

    let commandName = executable.lastPathComponent
    let exitCode = try await withThrowingTaskGroup(of: Int32.self) { group in
      group.addTask {
        for await status in termination { return status }
        return -1
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw InventoryError.commandTimedOut(commandName)
      }

      do {
        guard let first = try await group.next() else {
          throw InventoryError.commandFailed(commandName, -1, "No termination status")
        }
        group.cancelAll()
        return first
      } catch {
        if processBox.process.isRunning {
          Darwin.kill(processBox.process.processIdentifier, SIGTERM)
          try? await Task.sleep(for: .milliseconds(150))
          if processBox.process.isRunning {
            Darwin.kill(processBox.process.processIdentifier, SIGKILL)
          }
        }
        group.cancelAll()
        throw error
      }
    }

    outputPipe.fileHandleForReading.readabilityHandler = nil
    errorPipe.fileHandleForReading.readabilityHandler = nil
    output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
    errors.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

    if output.exceededLimit || errors.exceededLimit {
      throw InventoryError.outputLimitExceeded(commandName)
    }

    return CommandResult(
      standardOutput: output.snapshot(),
      standardError: errors.snapshot(),
      exitCode: exitCode
    )
  }
}
