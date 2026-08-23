import AppIntents
import SwiftUI
import WatchioModels
import WatchioStorage
import WidgetKit

enum WidgetViewMode: String, AppEnum {
  case services, ai, ports, health

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "View")
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .services: "Services", .ai: "AI activity", .ports: "Ports", .health: "Health",
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
    .padding(family == .systemSmall ? 13 : 14)
    .containerBackground(for: .widget) {
      WatchioSurface()
    }
    .environment(\.colorScheme, .dark)
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

  private var aiActivities: [DetectedAIActivity] {
    guard entry.configuration.projectScope == .single,
      let name = entry.configuration.projectName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    else { return entry.snapshot.aiActivities }
    return entry.snapshot.aiActivities.filter {
      $0.projectName?.localizedCaseInsensitiveCompare(name) == .orderedSame
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
    case .ai:
      if family == .systemSmall {
        smallAIActivity
      } else {
        aiActivityList(limit: family == .systemLarge ? 4 : 3)
      }
    case .ports:
      portList
    case .health:
      healthView
    }
  }

  private var smallAIActivity: some View {
    VStack(spacing: 0) {
      widgetHeader
      Spacer()
      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [Color.purple.opacity(0.18), .clear], center: .center, startRadius: 0,
              endRadius: 42)
          )
        Circle().stroke(Color.purple.opacity(0.25), lineWidth: 1)
        VStack(spacing: 1) {
          Text(aiActivities.count, format: .number)
            .font(.system(size: 28, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(red: 0.85, green: 0.76, blue: 1))
          Text("AI ACTIVE")
            .font(.system(size: 7.5, weight: .bold, design: .rounded))
            .tracking(0.9)
            .foregroundStyle(WatchioPalette.secondaryText)
        }
      }
      .frame(width: 76, height: 76)
      Spacer()
      Text(aiActivities.isEmpty ? "No AI activity" : aiProjectSummary)
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
      HStack(spacing: 5) {
        ForEach(Array(aiActivities.prefix(3))) { activity in
          AIToolGlyph(tool: activity.tool, size: 20)
        }
      }
      .frame(height: 22)
    }
  }

  private var smallServices: some View {
    VStack(spacing: 0) {
      widgetHeader
      Spacer()
      ZStack {
        Circle()
          .fill(
            RadialGradient(
              colors: [WatchioPalette.accent.opacity(0.12), .clear],
              center: .center,
              startRadius: 0,
              endRadius: 48
            )
          )
        Circle().stroke(WatchioPalette.accent.opacity(0.22), lineWidth: 1)
        Circle().stroke(WatchioPalette.accent.opacity(0.04), lineWidth: 7)
        VStack(spacing: 1) {
          Text(services.count, format: .number)
            .font(.system(size: 28, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(red: 0.82, green: 1, blue: 0.66))
            .contentTransition(.numericText())
          Text("LIVE")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(WatchioPalette.secondaryText)
        }
      }
      .frame(width: 76, height: 76)
      Spacer()
      Text(services.isEmpty ? "No services detected" : "Systems nominal")
        .font(.system(size: 12, weight: .semibold))
      HStack(spacing: 7) {
        ForEach(Array(Set(services.flatMap(\.ports).map(\.port))).sorted().prefix(3), id: \.self) {
          port in
          Text(":\(port)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(WatchioPalette.secondaryText)
        }
      }
      .frame(height: 13)
    }
  }

  private func serviceList(limit: Int) -> some View {
    VStack(alignment: .leading, spacing: family == .systemLarge ? 7 : 4) {
      widgetHeader
      ForEach(Array(services.prefix(limit))) { service in
        WidgetServiceRow(service: service, expanded: family == .systemLarge)
      }
      if services.isEmpty {
        Text("No services detected").font(.caption).foregroundStyle(WatchioPalette.secondaryText)
      }
      Spacer(minLength: 0)
      if family == .systemLarge { aggregateFooter }
    }
  }

  private func aiActivityList(limit: Int) -> some View {
    VStack(alignment: .leading, spacing: family == .systemLarge ? 7 : 4) {
      widgetHeader
      ForEach(Array(aiActivities.prefix(limit))) { activity in
        WidgetAIActivityRow(activity: activity, expanded: family == .systemLarge)
      }
      if aiActivities.isEmpty {
        Text("No AI activity").font(.caption).foregroundStyle(WatchioPalette.secondaryText)
      }
      Spacer(minLength: 0)
      if family == .systemLarge { aiAggregateFooter }
    }
  }

  private var portList: some View {
    VStack(alignment: .leading, spacing: family == .systemLarge ? 7 : 4) {
      widgetHeader
      ForEach(
        Array(
          services.flatMap { service in service.ports.map { (service, $0) } }.prefix(
            family == .systemSmall ? 3 : 6)), id: \.1.id
      ) { item in
        HStack(spacing: 8) {
          if family != .systemSmall {
            RuntimeGlyph(runtime: item.0.runtime, serviceName: item.0.name, size: 26)
          }
          Text(item.1.displayValue)
            .font(.system(.headline, design: .monospaced, weight: .semibold))
            .foregroundStyle(WatchioPalette.accent)
          Text(item.1.transport.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(WatchioPalette.secondaryText)
          Spacer()
          if family != .systemSmall {
            Text(item.0.name).font(.caption).lineLimit(1).foregroundStyle(.white.opacity(0.8))
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, family == .systemLarge ? 6 : 3)
        .background(WatchioPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      Spacer(minLength: 0)
    }
  }

  private var healthView: some View {
    VStack(alignment: .leading, spacing: family == .systemLarge ? 8 : 5) {
      widgetHeader
      ForEach(entry.snapshot.sourceHealth.prefix(family == .systemSmall ? 3 : 4)) { source in
        HStack(spacing: 8) {
          Image(
            systemName: source.state == .available
              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
          )
          .foregroundStyle(source.state == .available ? WatchioPalette.accentSoft : .orange)
          Text(source.source.rawValue.capitalized).fontWeight(.semibold)
          Spacer()
          if family != .systemSmall {
            Text(source.state.rawValue.capitalized).foregroundStyle(WatchioPalette.secondaryText)
          }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, family == .systemLarge ? 8 : 5)
        .background(WatchioPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      Spacer(minLength: 0)
    }
  }

  private var widgetHeader: some View {
    HStack(spacing: 8) {
      WatchioMark(compact: true)
      if family != .systemSmall {
        VStack(alignment: .leading, spacing: 1) {
          Text(entry.configuration.viewMode == .ai ? "AI activity" : "Local development")
            .font(.system(size: 11, weight: .semibold))
          Text(headerSubtitle)
            .font(.system(size: 8.5))
            .foregroundStyle(WatchioPalette.secondaryText)
        }
      }
      Spacer()
      Text(entry.snapshot.generatedAt, style: .timer)
        .font(.system(size: 8.5, design: .monospaced))
        .foregroundStyle(WatchioPalette.secondaryText)
        .monospacedDigit()
    }
  }

  private var headerSubtitle: String {
    if entry.configuration.viewMode == .ai {
      return "\(aiActivities.count) active · \(aiProjectCount) projects"
    }
    return "\(services.count) running · all projects"
  }

  private var aiProjectCount: Int {
    Set(aiActivities.compactMap(\.projectName)).count
  }

  private var aiProjectSummary: String {
    aiProjectCount == 1 ? "1 project" : "\(aiProjectCount) projects"
  }

  private var aggregateFooter: some View {
    HStack(spacing: 8) {
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
      Divider().overlay(Color.white.opacity(0.09)).padding(.vertical, 2)
      MiniTrend(samples: entry.trend)
        .frame(width: 86, height: 34)
        .accessibilityLabel("Recent in-memory CPU activity")
    }
    .padding(10)
    .background(WatchioPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(WatchioPalette.cardBorder, lineWidth: 1)
    }
  }

  private var aiAggregateFooter: some View {
    HStack {
      metric("CPU", String(format: "%.1f%%", aiActivities.map(\.cpuPercent).reduce(0, +)))
      metric(
        "Memory",
        ByteCountFormatter.string(
          fromByteCount: Int64(aiActivities.map(\.memoryBytes).reduce(0, +)),
          countStyle: .memory
        ))
      metric("Processes", String(aiActivities.map(\.processCount).reduce(0, +)))
      metric("Projects", String(aiProjectCount))
    }
    .padding(10)
    .background(WatchioPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(WatchioPalette.cardBorder, lineWidth: 1)
    }
  }

  private func metric(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label).font(.system(size: 8)).foregroundStyle(WatchioPalette.secondaryText)
      Text(value).font(.system(size: 10, weight: .semibold, design: .monospaced))
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func stateView(_ title: String, _ symbol: String, _ detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      WatchioMark(compact: true)
      Spacer()
      Image(systemName: symbol).font(.title2).foregroundStyle(WatchioPalette.secondaryText)
      Text(title).font(.headline)
      Text(detail).font(.caption).foregroundStyle(WatchioPalette.secondaryText).lineLimit(2)
    }
  }
}

private struct WidgetServiceRow: View {
  let service: DetectedService
  let expanded: Bool

  var body: some View {
    Link(destination: URL(string: "watchio://service/\(service.id)")!) {
      HStack(spacing: expanded ? 9 : 7) {
        RuntimeGlyph(
          runtime: service.runtime,
          serviceName: service.name,
          size: expanded ? 34 : 26
        )
        VStack(alignment: .leading, spacing: expanded ? 2 : 0) {
          HStack(spacing: 5) {
            Text(service.name)
              .font(.system(size: expanded ? 11 : 9.5, weight: .semibold))
              .lineLimit(1)
            Circle()
              .fill(WatchioPalette.accentSoft)
              .frame(width: 4, height: 4)
          }
          Text(service.projectName)
            .font(.system(size: expanded ? 8.5 : 7.5))
            .foregroundStyle(WatchioPalette.secondaryText)
            .lineLimit(1)
        }
        Spacer()
        if let port = service.ports.first {
          Text(port.displayValue)
            .font(.system(size: expanded ? 10 : 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(WatchioPalette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
              WatchioPalette.accent.opacity(0.085),
              in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        } else if expanded {
          Text("worker")
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(WatchioPalette.secondaryText)
        }
        Text(widgetUptime(service))
          .font(.system(size: expanded ? 8.5 : 7.5, design: .monospaced))
          .foregroundStyle(WatchioPalette.secondaryText)
          .frame(width: expanded ? 34 : 27, alignment: .trailing)
      }
      .padding(.horizontal, expanded ? 9 : 6)
      .padding(.vertical, expanded ? 6 : 2)
      .background(WatchioPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(WatchioPalette.cardBorder, lineWidth: 1)
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

private struct WidgetAIActivityRow: View {
  let activity: DetectedAIActivity
  let expanded: Bool

  var body: some View {
    Link(destination: URL(string: "watchio://ai/\(activity.id)")!) {
      HStack(spacing: expanded ? 9 : 7) {
        AIToolGlyph(tool: activity.tool, size: expanded ? 34 : 26)
        VStack(alignment: .leading, spacing: expanded ? 2 : 0) {
          HStack(spacing: 5) {
            Text(activity.tool.displayName)
              .font(.system(size: expanded ? 11 : 9.5, weight: .semibold))
              .lineLimit(1)
            Circle()
              .fill(WatchioPalette.accentSoft)
              .frame(width: 4, height: 4)
          }
          Text(activity.projectName ?? "No project context")
            .font(.system(size: expanded ? 8.5 : 7.5))
            .foregroundStyle(WatchioPalette.secondaryText)
            .lineLimit(1)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          HStack(spacing: 6) {
            Text(activity.host.displayName)
              .font(.system(size: expanded ? 8 : 7.5, weight: .medium, design: .rounded))
              .foregroundStyle(.white.opacity(0.68))
            Text(widgetUptime(activity))
              .font(.system(size: expanded ? 8.5 : 7.5, design: .monospaced))
              .foregroundStyle(WatchioPalette.secondaryText)
          }
          Text("CPU \(widgetCPU(activity.cpuPercent)) · RAM \(widgetMemory(activity.memoryBytes))")
            .font(.system(size: expanded ? 7.5 : 6.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.56))
            .lineLimit(1)
        }
      }
      .padding(.horizontal, expanded ? 9 : 6)
      .padding(.vertical, expanded ? 6 : 2)
      .background(WatchioPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(WatchioPalette.cardBorder, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private func widgetUptime(_ activity: DetectedAIActivity) -> String {
    let value = activity.uptime()
    if value >= 3_600 { return "\(Int(value / 3_600))h" }
    return "\(max(1, Int(value / 60)))m"
  }

  private func widgetCPU(_ value: Double) -> String {
    String(format: "%.1f%%", value)
  }

  private func widgetMemory(_ bytes: UInt64) -> String {
    let mebibytes = Double(bytes) / 1_048_576
    if mebibytes >= 1_024 { return String(format: "%.1f GB", mebibytes / 1_024) }
    return "\(Int(mebibytes.rounded())) MB"
  }
}

private struct MiniTrend: View {
  let samples: [WidgetResourceSample]

  var body: some View {
    GeometryReader { geometry in
      let maximum = max(samples.map(\.cpuPercent).max() ?? 1, 1)
      HStack(alignment: .bottom, spacing: 3) {
        ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
          RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(
              LinearGradient(
                colors: [WatchioPalette.accentSoft, WatchioPalette.accent],
                startPoint: .bottom,
                endPoint: .top
              )
            )
            .frame(
              maxWidth: .infinity,
              minHeight: 3,
              maxHeight: max(3, geometry.size.height * CGFloat(sample.cpuPercent / maximum))
            )
        }
      }
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
    .contentMarginsDisabled()
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
