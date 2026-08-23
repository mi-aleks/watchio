import Foundation
import WatchioModels

public enum PSInventoryParser {
  public static func parse(_ output: String) -> [ProcessRecord] {
    output.split(whereSeparator: \.isNewline).compactMap(parseLine)
  }

  public static func parseLine(_ line: Substring) -> ProcessRecord? {
    let fields = line.split(maxSplits: 8, whereSeparator: \.isWhitespace)
    guard fields.count == 9,
      let uid = UInt32(fields[0]),
      let pid = Int32(fields[1]),
      let parentPID = Int32(fields[2]),
      let processGroupID = Int32(fields[3]),
      let elapsed = parseElapsed(String(fields[5])),
      let cpu = Double(fields[6]),
      let rssKilobytes = UInt64(fields[7])
    else { return nil }

    let ttyValue = String(fields[4])
    return ProcessRecord(
      uid: uid,
      pid: pid,
      parentPID: parentPID,
      processGroupID: processGroupID,
      tty: ttyValue == "??" ? nil : ttyValue,
      elapsedSeconds: elapsed,
      cpuPercent: cpu,
      memoryBytes: rssKilobytes * 1_024,
      executablePath: String(fields[8])
    )
  }

  public static func parseElapsed(_ value: String) -> TimeInterval? {
    let daySplit = value.split(separator: "-", maxSplits: 1)
    let days: Double
    let clock: Substring
    if daySplit.count == 2 {
      guard let parsedDays = Double(daySplit[0]) else { return nil }
      days = parsedDays
      clock = daySplit[1]
    } else {
      days = 0
      clock = Substring(value)
    }

    let units = clock.split(separator: ":").compactMap(Double.init)
    guard units.count == 2 || units.count == 3 else { return nil }
    let hours = units.count == 3 ? units[0] : 0
    let minutes = units.count == 3 ? units[1] : units[0]
    let seconds = units.count == 3 ? units[2] : units[1]
    return days * 86_400 + hours * 3_600 + minutes * 60 + seconds
  }
}

public enum LsofInventoryParser {
  public static func parseListeners(_ output: String, transport: NetworkTransport) -> [PortRecord] {
    var currentPID: Int32?
    var records: [PortRecord] = []

    for line in output.split(whereSeparator: \.isNewline) {
      guard let field = line.first else { continue }
      let value = String(line.dropFirst())
      switch field {
      case "p": currentPID = Int32(value)
      case "n":
        guard let pid = currentPID, let endpoint = parseEndpoint(value, transport: transport) else {
          continue
        }
        records.append(PortRecord(pid: pid, endpoint: endpoint))
      default: continue
      }
    }
    return Array(Set(records)).sorted { lhs, rhs in
      lhs.pid == rhs.pid ? lhs.endpoint.port < rhs.endpoint.port : lhs.pid < rhs.pid
    }
  }

  public static func parseWorkingDirectories(_ output: String) -> [Int32: String] {
    var currentPID: Int32?
    var awaitingPath = false
    var result: [Int32: String] = [:]

    for line in output.split(whereSeparator: \.isNewline) {
      guard let field = line.first else { continue }
      let value = String(line.dropFirst())
      switch field {
      case "p":
        currentPID = Int32(value)
        awaitingPath = false
      case "f": awaitingPath = value == "cwd"
      case "n" where awaitingPath:
        if let currentPID { result[currentPID] = value }
        awaitingPath = false
      default: continue
      }
    }
    return result
  }

  private static func parseEndpoint(_ value: String, transport: NetworkTransport)
    -> ListeningEndpoint?
  {
    let localValue = value.components(separatedBy: "->").first ?? value
    guard let separator = localValue.lastIndex(of: ":") else { return nil }
    var address = String(localValue[..<separator])
    let portValue = localValue[localValue.index(after: separator)...]
    guard let port = Int(portValue), (1...65_535).contains(port) else { return nil }
    if address.hasPrefix("[") && address.hasSuffix("]") {
      address.removeFirst()
      address.removeLast()
    }
    return ListeningEndpoint(transport: transport, address: address, port: port)
  }
}
