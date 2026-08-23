import Foundation
import WatchioModels

public actor DockerInventoryProvider: ContainerInventoryProviding {
  private let runner: any CommandRunning
  private let executable: URL?
  private let homePath: String
  private var cachedRecords: [String: ContainerRecord] = [:]
  private var cachedContextEndpoint: String?

  public init(
    runner: any CommandRunning = ProcessCommandRunner(),
    executable: URL? = DockerInventoryProvider.defaultExecutable(),
    homePath: String = FileManager.default.homeDirectoryForCurrentUser.path
  ) {
    self.runner = runner
    self.executable = executable
    self.homePath = homePath
  }

  public func containers() async throws -> [ContainerRecord] {
    guard let executable else { throw InventoryError.unavailable("Docker CLI") }
    let contextEndpoint = try await localContextEndpoint(executable: executable)
    if contextEndpoint != cachedContextEndpoint {
      cachedRecords.removeAll()
      cachedContextEndpoint = contextEndpoint
    }
    let list = try await runner.run(
      executable: executable,
      arguments: ["ps", "-q", "--no-trunc"],
      timeout: .seconds(5)
    )
    guard list.exitCode == 0 else {
      throw InventoryError.commandFailed("docker ps", list.exitCode, list.errorString)
    }

    let activeIDs = Set(list.outputString.split(whereSeparator: \.isNewline).map(String.init))
    cachedRecords = cachedRecords.filter { activeIDs.contains($0.key) }
    let newIDs = activeIDs.subtracting(cachedRecords.keys)
    if !newIDs.isEmpty {
      let inspect = try await runner.run(
        executable: executable,
        arguments: ["inspect"] + newIDs.sorted(),
        timeout: .seconds(7)
      )
      guard inspect.exitCode == 0 else {
        throw InventoryError.commandFailed("docker inspect", inspect.exitCode, inspect.errorString)
      }
      let decoded: [DockerInspect]
      do {
        decoded = try JSONDecoder().decode([DockerInspect].self, from: inspect.standardOutput)
      } catch {
        throw InventoryError.malformedOutput("docker inspect")
      }
      for container in decoded {
        if let record = makeRecord(container) { cachedRecords[record.id] = record }
      }
    }

    return cachedRecords.values.sorted {
      ($0.projectName, $0.name, $0.id) < ($1.projectName, $1.name, $1.id)
    }
  }

  public static func defaultExecutable(fileManager: FileManager = .default) -> URL? {
    [
      "/opt/homebrew/bin/docker",
      "/usr/local/bin/docker",
      "/Applications/Docker.app/Contents/Resources/bin/docker",
    ].first(where: fileManager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
  }

  private func localContextEndpoint(executable: URL) async throws -> String {
    let context = try await runner.run(
      executable: executable,
      arguments: ["context", "inspect", "--format", "{{json .Endpoints.docker.Host}}"],
      timeout: .seconds(4)
    )
    guard context.exitCode == 0 else {
      throw InventoryError.commandFailed(
        "docker context inspect", context.exitCode, context.errorString)
    }
    let data = Data(context.outputString.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    guard let endpoint = try? JSONDecoder().decode(String.self, from: data),
      endpoint.hasPrefix("unix://")
    else {
      throw InventoryError.unavailable("Local Docker context")
    }
    return endpoint
  }

  private func makeRecord(_ inspect: DockerInspect) -> ContainerRecord? {
    let labels = inspect.config?.labels ?? [:]
    guard let project = labels["com.docker.compose.project"],
      let service = labels["com.docker.compose.service"]
    else { return nil }
    let rawPath = labels["com.docker.compose.project.working_dir"]
    let safePath = rawPath.map(displayPath)
    let ports = (inspect.networkSettings?.ports ?? [:]).flatMap {
      key, bindings -> [ListeningEndpoint] in
      let transport: NetworkTransport = key.hasSuffix("/udp") ? .udp : .tcp
      return (bindings ?? []).compactMap { binding in
        guard let port = Int(binding.hostPort), (1...65_535).contains(port) else { return nil }
        return ListeningEndpoint(transport: transport, address: binding.hostIP, port: port)
      }
    }
    return ContainerRecord(
      id: inspect.id,
      name: service.isEmpty
        ? inspect.name.trimmingCharacters(in: CharacterSet(charactersIn: "/")) : service,
      projectName: project,
      projectPath: safePath,
      ports: Array(Set(ports)).sorted { $0.port < $1.port },
      startedAt: inspect.state?.startedAt.flatMap(parseDockerDate)
    )
  }

  private func displayPath(_ path: String) -> String {
    guard path == homePath || path.hasPrefix(homePath + "/") else {
      return URL(fileURLWithPath: path).lastPathComponent
    }
    return "~" + path.dropFirst(homePath.count)
  }

  private func parseDockerDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}

private struct DockerInspect: Decodable {
  let id: String
  let name: String
  let config: Config?
  let state: State?
  let networkSettings: NetworkSettings?

  enum CodingKeys: String, CodingKey {
    case id = "Id"
    case name = "Name"
    case config = "Config"
    case state = "State"
    case networkSettings = "NetworkSettings"
  }

  struct Config: Decodable {
    let labels: [String: String]?
    enum CodingKeys: String, CodingKey { case labels = "Labels" }
  }

  struct State: Decodable {
    let startedAt: String?
    enum CodingKeys: String, CodingKey { case startedAt = "StartedAt" }
  }

  struct NetworkSettings: Decodable {
    let ports: [String: [PortBinding]?]?
    enum CodingKeys: String, CodingKey { case ports = "Ports" }
  }

  struct PortBinding: Decodable {
    let hostIP: String
    let hostPort: String
    enum CodingKeys: String, CodingKey {
      case hostIP = "HostIp"
      case hostPort = "HostPort"
    }
  }
}
