import AppIntents
import SwiftUI
import WatchioModels
import WatchioStorage
import WidgetKit

enum WidgetViewMode: String, AppEnum {
  case services, ports, health

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "View")
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .services: "Services", .ports: "Ports", .health: "Health",
  ]
}

enum WidgetProjectScope: String, AppEnum {
  case all, single

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Project scope")
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .all: "All projects", .single: "Single project",
  ]
}

struct WatchioWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Watchio"
  static let description = IntentDescription(
    "Choose the Watchio view and optionally focus one project.")

  @Parameter(title: "View", default: .services)
  var viewMode: WidgetViewMode

  @Parameter(title: "Scope", default: .all)
  var projectScope: WidgetProjectScope

  @Parameter(title: "Project name", description: "Used only with Single project scope")
  var projectName: String?
}

struct WatchioEntry: TimelineEntry {
  let date: Date
  let snapshot: WatchioSnapshot
  let configuration: WatchioWidgetIntent
  let readState: WidgetReadState
  let trend: [WidgetResourceSample]
}

enum WidgetReadState: Sendable {
  case ready, missing, updateRequired, corrupt
}

struct WatchioTimelineProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> WatchioEntry {
    WatchioEntry(
      date: .now, snapshot: DemoData.snapshot, configuration: WatchioWidgetIntent(),
      readState: .ready, trend: WidgetResourceSample.demo
    )
  }

  func snapshot(for configuration: WatchioWidgetIntent, in context: Context) async -> WatchioEntry {
    if context.isPreview {
      return WatchioEntry(
        date: .now, snapshot: DemoData.snapshot, configuration: configuration,
        readState: .ready, trend: WidgetResourceSample.demo
      )
    }
    return await load(configuration: configuration, date: .now)
  }

  func timeline(for configuration: WatchioWidgetIntent, in context: Context) async -> Timeline<
    WatchioEntry
  > {
    let now = Date()
    let current = await load(configuration: configuration, date: now)
    var entries = [current]
    if current.readState == .ready {
      let offlineDate = max(
        now.addingTimeInterval(31), current.snapshot.generatedAt.addingTimeInterval(31))
      entries.append(
        WatchioEntry(
          date: offlineDate,
          snapshot: current.snapshot,
          configuration: configuration,
          readState: current.readState,
          trend: current.trend
        ))
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
  }

  private func load(configuration: WatchioWidgetIntent, date: Date) async -> WatchioEntry {
    switch await JSONSnapshotStore().load() {
    case .snapshot(let snapshot):
      let cpu = snapshot.services.compactMap(\.cpuPercent).reduce(0, +)
      let memory = snapshot.services.compactMap(\.memoryBytes).reduce(0, +)
      let trend = await WidgetTrendCache.shared.record(cpu: cpu, memory: memory, at: date)
      return WatchioEntry(
        date: date, snapshot: snapshot, configuration: configuration,
        readState: .ready, trend: trend
      )
    case .missing:
      return WatchioEntry(
        date: date, snapshot: .empty, configuration: configuration, readState: .missing, trend: [])
    case .updateRequired:
      return WatchioEntry(
        date: date, snapshot: .empty, configuration: configuration, readState: .updateRequired,
        trend: [])
    case .corrupt:
      return WatchioEntry(
        date: date, snapshot: .empty, configuration: configuration, readState: .corrupt, trend: [])
    }
  }
}

struct WatchioWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: WatchioEntry

  var body: some View {
    Group {
      if entry.readState == .updateRequired {
        stateView("Update required", "arrow.down.circle", "Open a newer Watchio version")
      } else if entry.readState == .corrupt {
        stateView("Snapshot unavailable", "exclamationmark.triangle", "Open Watchio to refresh")
      } else if entry.readState == .missing {
        stateView("Open Watchio", "terminal", "The collector has not written a snapshot")
      } else if isOffline {
        stateView(
          "Watchio is offline", "pause.circle",
          "Last seen \(entry.snapshot.generatedAt.formatted(.relative(presentation: .named)))")
      } else {
        content
      }
    }
    .padding()
    .containerBackground(for: .widget) {
      LinearGradient(
        colors: [Color.accentColor.opacity(0.12), Color.clear], startPoint: .topLeading,
        endPoint: .bottomTrailing)
    }
    .widgetURL(URL(string: "watchio://services"))
  }

  private var services: [DetectedService] {
    guard entry.configuration.projectScope == .single,
      let name = entry.configuration.projectName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    else { return entry.snapshot.services }
    return entry.snapshot.services.filter {
      $0.projectName.localizedCaseInsensitiveCompare(name) == .orderedSame
    }
  }

  private var isOffline: Bool {
    entry.snapshot.isStale(referenceDate: entry.date, threshold: 30)
      || entry.snapshot.collectorState == .offline
  }

  @ViewBuilder private var content: some View {
    switch entry.configuration.viewMode {
    case .services:
      if family == .systemSmall {
        smallServices
      } else {
        serviceList(limit: family == .systemLarge ? 4 : 3)
      }
    case .ports:
      portList
    case .health:
      healthView
    }
  }

  private var smallServices: some View {
    VStack(alignment: .leading, spacing: 5) {
      widgetHeader
      Spacer()
      Text(services.count, format: .number)
        .font(.system(size: 42, weight: .black, design: .rounded))
        .contentTransition(.numericText())
      Text(services.count == 1 ? "service is live" : "services are live")
        .font(.caption).foregroundStyle(.secondary)
      HStack(spacing: 5) {
        ForEach(Array(Set(services.flatMap(\.ports).map(\.port))).sorted().prefix(3), id: \.self) {
          port in
          Text(":\(port)").font(.system(.caption2, design: .monospaced, weight: .semibold))
        }
      }
    }
  }

  private func serviceList(limit: Int) -> some View {
    VStack(alignment: .leading, spacing: family == .systemLarge ? 9 : 6) {
      widgetHeader
      ForEach(Array(services.prefix(limit))) { service in
        WidgetServiceRow(service: service)
      }
      if services.isEmpty { Text("No services detected").foregroundStyle(.secondary) }
      Spacer(minLength: 0)
      if family == .systemLarge { aggregateFooter }
    }
  }

  private var portList: some View {
    VStack(alignment: .leading, spacing: 8) {
      widgetHeader
      ForEach(
        Array(
          services.flatMap { service in service.ports.map { (service, $0) } }.prefix(
            family == .systemSmall ? 3 : 6)), id: \.1.id
      ) { item in
        HStack {
          Text(item.1.displayValue).font(.system(.headline, design: .monospaced, weight: .bold))
          Text(item.1.transport.rawValue.uppercased()).font(.caption2).foregroundStyle(.secondary)
          Spacer()
          if family != .systemSmall { Text(item.0.name).lineLimit(1).foregroundStyle(.secondary) }
        }
      }
      Spacer(minLength: 0)
    }
  }

  private var healthView: some View {
    VStack(alignment: .leading, spacing: 8) {
      widgetHeader
      ForEach(entry.snapshot.sourceHealth.prefix(family == .systemSmall ? 3 : 4)) { source in
        HStack {
          Circle().fill(source.state == .available ? .green : .orange).frame(width: 7, height: 7)
          Text(source.source.rawValue.capitalized)
          Spacer()
          if family != .systemSmall {
            Text(source.state.rawValue.capitalized).foregroundStyle(.secondary)
          }
        }
        .font(.caption)
      }
      Spacer(minLength: 0)
    }
  }

  private var widgetHeader: some View {
    HStack {
      Text("w:").font(.system(.headline, design: .monospaced, weight: .black)).foregroundStyle(
        .tint)
      Spacer()
      Text(entry.snapshot.generatedAt, style: .timer).font(.caption2).foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }

  private var aggregateFooter: some View {
    VStack(spacing: 6) {
      HStack {
        metric("CPU", String(format: "%.1f%%", services.compactMap(\.cpuPercent).reduce(0, +)))
        metric(
          "Memory",
          ByteCountFormatter.string(
            fromByteCount: Int64(services.compactMap(\.memoryBytes).reduce(0, +)),
            countStyle: .memory
          ))
        metric("Listeners", String(services.flatMap(\.ports).count))
      }
      MiniTrend(samples: entry.trend)
        .frame(height: 24)
        .accessibilityLabel("Recent in-memory CPU activity")
    }
  }

  private func metric(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.system(.caption, design: .monospaced, weight: .semibold))
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func stateView(_ title: String, _ symbol: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("w:").font(.system(.headline, design: .monospaced, weight: .black)).foregroundStyle(
        .tint)
      Spacer()
      Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
      Text(title).font(.headline)
      Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
    }
  }
}

private struct WidgetServiceRow: View {
  let service: DetectedService

  var body: some View {
    Link(destination: URL(string: "watchio://service/\(service.id)")!) {
      HStack(spacing: 8) {
        Text(service.runtime.badge)
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .frame(width: 26, height: 20)
          .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
        VStack(alignment: .leading, spacing: 1) {
          Text(service.name).font(.caption.weight(.semibold)).lineLimit(1)
          Text(service.projectName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        if let port = service.ports.first {
          Text(port.displayValue).font(.system(.caption, design: .monospaced, weight: .semibold))
        }
        Text(widgetUptime(service)).font(.caption2).foregroundStyle(.secondary).frame(
          width: 42, alignment: .trailing)
      }
    }
    .buttonStyle(.plain)
  }

  private func widgetUptime(_ service: DetectedService) -> String {
    guard let value = service.uptime() else { return "—" }
    if value >= 3_600 { return "\(Int(value / 3_600))h" }
    return "\(max(1, Int(value / 60)))m"
  }
}

private struct MiniTrend: View {
  let samples: [WidgetResourceSample]

  var body: some View {
    GeometryReader { geometry in
      let maximum = max(samples.map(\.cpuPercent).max() ?? 1, 1)
      Path { path in
        for (index, sample) in samples.enumerated() {
          let x =
            samples.count <= 1
            ? 0 : geometry.size.width * CGFloat(index) / CGFloat(samples.count - 1)
          let y = geometry.size.height * (1 - CGFloat(sample.cpuPercent / maximum))
          if index == 0 {
            path.move(to: CGPoint(x: x, y: y))
          } else {
            path.addLine(to: CGPoint(x: x, y: y))
          }
        }
      }
      .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
  }
}

struct WidgetResourceSample: Sendable {
  let date: Date
  let cpuPercent: Double
  let memoryBytes: UInt64

  static let demo = stride(from: 0, through: 7, by: 1).map {
    WidgetResourceSample(
      date: .now.addingTimeInterval(Double($0 - 7) * 10), cpuPercent: [2, 5, 3, 8, 4, 7, 6, 9][$0],
      memoryBytes: 280_000_000)
  }
}

actor WidgetTrendCache {
  static let shared = WidgetTrendCache()
  private var samples: [WidgetResourceSample] = []

  func record(cpu: Double, memory: UInt64, at date: Date) -> [WidgetResourceSample] {
    samples.append(WidgetResourceSample(date: date, cpuPercent: cpu, memoryBytes: memory))
    samples = Array(samples.suffix(20))
    return samples
  }
}

struct WatchioWidget: Widget {
  let kind = "WatchioWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind, intent: WatchioWidgetIntent.self, provider: WatchioTimelineProvider()
    ) { entry in
      WatchioWidgetView(entry: entry)
    }
    .configurationDisplayName("Watchio")
    .description("See the development services and ports Watchio detected locally.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct WatchioWidgetBundle: WidgetBundle {
  var body: some Widget { WatchioWidget() }
}

#Preview(as: .systemSmall) {
  WatchioWidget()
} timeline: {
  WatchioEntry(
    date: .now, snapshot: DemoData.snapshot, configuration: WatchioWidgetIntent(),
    readState: .ready, trend: WidgetResourceSample.demo)
}

#Preview(as: .systemMedium) {
  WatchioWidget()
} timeline: {
  WatchioEntry(
    date: .now, snapshot: DemoData.snapshot, configuration: WatchioWidgetIntent(),
    readState: .ready, trend: WidgetResourceSample.demo)
}

#Preview(as: .systemLarge) {
  WatchioWidget()
} timeline: {
  WatchioEntry(
    date: .now, snapshot: DemoData.snapshot, configuration: WatchioWidgetIntent(),
    readState: .ready, trend: WidgetResourceSample.demo)
}
