import AppKit
import SwiftUI
import WatchioModels

struct MenuBarContentView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      header
      if !model.hasCompletedOnboarding { onboarding }
      Picker("View", selection: $model.selectedMode) {
        ForEach(AppModel.Mode.allCases) { mode in Text(mode.rawValue).tag(mode) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 14)
      .padding(.bottom, 12)

      Divider()
      Group {
        switch model.selectedMode {
        case .services: services
        case .ports: ports
        case .health: health
        }
      }
      .frame(minHeight: 240, maxHeight: 420)
      Divider()
      footer
    }
    .frame(width: 420)
    .background(.ultraThinMaterial)
    .onOpenURL { model.handleDeepLink($0) }
  }

  private var onboarding: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Watchio observes your local development services", systemImage: "eye")
        .font(.headline)
      Text(
        "Scanning stays on this Mac. Watchio never reads environment values or changes a process."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Got it") { model.completeOnboarding() }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("complete-onboarding")
      }
    }
    .padding(12)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
    .accessibilityIdentifier("onboarding")
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text("w:")
          .font(.system(.title2, design: .monospaced, weight: .black))
          .foregroundStyle(.tint)
        Text(statusText).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if model.isScanning { ProgressView().controlSize(.small) }
      Button {
        Task { await model.scanNow() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.plain)
      .help("Scan now")
      .keyboardShortcut("r", modifiers: .command)
      .accessibilityIdentifier("scan-now")
    }
    .padding(14)
  }

  private var statusText: String {
    let count = model.snapshot.services.count
    return count == 1 ? "1 development service" : "\(count) development services"
  }

  private var services: some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        if model.snapshot.services.isEmpty { emptyState }
        ForEach(model.snapshot.services) { service in
          ServiceRow(service: service, selected: model.selectedServiceID == service.id) {
            model.selectedServiceID = model.selectedServiceID == service.id ? nil : service.id
          }
          if model.selectedServiceID == service.id { ServiceDetail(service: service) }
        }
      }
      .padding(10)
    }
  }

  private var ports: some View {
    List {
      ForEach(
        model.snapshot.services.flatMap { service in service.ports.map { (service, $0) } },
        id: \.1.id
      ) { item in
        HStack {
          Text(item.1.displayValue).font(.system(.body, design: .monospaced, weight: .semibold))
          Text(item.1.transport.rawValue.uppercased()).font(.caption2).foregroundStyle(.secondary)
          Spacer()
          Text(item.0.name).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
      }
    }
    .listStyle(.plain)
    .overlay { if model.snapshot.services.allSatisfy(\.ports.isEmpty) { emptyState } }
  }

  private var health: some View {
    List(model.snapshot.sourceHealth) { source in
      HStack {
        Image(
          systemName: source.state == .available
            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(source.state == .available ? .green : .orange)
        VStack(alignment: .leading) {
          Text(source.source.rawValue.capitalized)
          if let message = source.message {
            Text(message).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        Text(source.state.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
      }
    }
    .listStyle(.plain)
  }

  private var emptyState: some View {
    ContentUnavailableView(
      "No development services",
      systemImage: "terminal",
      description: Text("Watchio only shows stable processes with strong development evidence.")
    )
  }

  private var footer: some View {
    HStack {
      Text("Updated \(model.snapshot.generatedAt, style: .relative)")
        .font(.caption2).foregroundStyle(.secondary)
      Spacer()
      SettingsLink { Label("Settings", systemImage: "gearshape") }
        .buttonStyle(.plain)
      Divider().frame(height: 14)
      Button("Quit") { NSApplication.shared.terminate(nil) }
        .buttonStyle(.plain)
        .keyboardShortcut("q", modifiers: .command)
    }
    .padding(12)
  }
}

private struct ServiceRow: View {
  let service: DetectedService
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        RuntimeBadge(runtime: service.runtime)
        VStack(alignment: .leading, spacing: 2) {
          Text(service.name).fontWeight(.medium).lineLimit(1)
          Text(service.projectPath ?? service.projectName).font(.caption).foregroundStyle(
            .secondary
          ).lineLimit(1)
        }
        Spacer()
        if let endpoint = service.ports.first {
          Text(endpoint.displayValue).font(
            .system(.callout, design: .monospaced, weight: .semibold))
        }
        Text(WatchioFormat.uptime(service)).font(.caption).foregroundStyle(.secondary).frame(
          width: 54, alignment: .trailing)
        Image(systemName: selected ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(
          .tertiary)
      }
      .padding(8)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
    .accessibilityIdentifier("service-\(service.id)")
  }
}

private struct ServiceDetail: View {
  let service: DetectedService

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
      detail("PID", service.representativePID.map(String.init) ?? "Container")
      detail("Processes", String(service.processCount))
      detail("CPU", service.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—")
      detail("Memory", WatchioFormat.bytes(service.memoryBytes))
      detail("Confidence", "\(service.confidence)%")
      GridRow {
        Text("Evidence").foregroundStyle(.secondary)
        Text(service.evidence.map(\.displayName).joined(separator: " · ")).lineLimit(3)
      }
    }
    .font(.caption)
    .padding(.horizontal, 10)
    .padding(.bottom, 8)
  }

  private func detail(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }
}
