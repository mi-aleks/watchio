import AppKit
import SwiftUI
import WatchioModels

struct MenuBarContentView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openSettings) private var openSettings

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
      .tint(WatchioPalette.accent)
      .padding(.horizontal, 16)
      .padding(.bottom, 14)

      Divider().overlay(Color.white.opacity(0.08))
      Group {
        switch model.selectedMode {
        case .services: services
        case .ai: aiActivity
        case .ports: ports
        case .health: health
        }
      }
      .frame(minHeight: 240, maxHeight: 420)
      Divider().overlay(Color.white.opacity(0.08))
      footer
    }
    .frame(width: 430)
    .background { WatchioSurface().ignoresSafeArea() }
    .environment(\.colorScheme, .dark)
    .onOpenURL { model.handleDeepLink($0) }
    .alert(
      "Process control",
      isPresented: Binding(
        get: { model.processControlNotice != nil },
        set: { if !$0 { model.processControlNotice = nil } }
      )
    ) {
      Button("OK") { model.processControlNotice = nil }
    } message: {
      Text(model.processControlNotice ?? "")
    }
  }

  private var onboarding: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Watchio observes your local development services", systemImage: "eye.fill")
        .font(.headline)
        .foregroundStyle(.white)
      Text(
        "Scanning stays on this Mac. Process control runs only after an explicit confirmation."
      )
      .font(.caption)
      .foregroundStyle(WatchioPalette.secondaryText)
      HStack {
        Spacer()
        Button("Got it") { model.completeOnboarding() }
          .keyboardShortcut(.defaultAction)
          .tint(WatchioPalette.accent)
          .accessibilityIdentifier("complete-onboarding")
      }
    }
    .padding(13)
    .background(WatchioPalette.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .stroke(WatchioPalette.cardBorder, lineWidth: 1)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 14)
    .accessibilityIdentifier("onboarding")
  }

  private var header: some View {
    HStack(spacing: 11) {
      WatchioMark()
      VStack(alignment: .leading, spacing: 2) {
        Text("Local development")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)
        Text(statusText)
          .font(.system(size: 10))
          .foregroundStyle(WatchioPalette.secondaryText)
      }
      Spacer()
      if model.isScanning {
        ProgressView().controlSize(.small).tint(WatchioPalette.accent)
      }
      Button {
        Task { await model.scanNow() }
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 28, height: 28)
          .background(Color.white.opacity(0.055), in: Circle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(WatchioPalette.secondaryText)
      .help("Scan now")
      .keyboardShortcut("r", modifiers: .command)
      .accessibilityIdentifier("scan-now")
    }
    .padding(16)
  }

  private var statusText: String {
    let services = model.snapshot.services.count
    let ai = model.snapshot.aiActivities.count
    if ai == 0 {
      return services == 1 ? "1 development service" : "\(services) development services"
    }
    return "\(services) services · \(ai) AI active"
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
      .padding(12)
    }
    .scrollIndicators(.hidden)
  }

  private var aiActivity: some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        if model.snapshot.aiActivities.isEmpty { aiEmptyState }
        ForEach(model.snapshot.aiActivities) { activity in
          AIActivityRow(
            activity: activity, selected: model.selectedAIActivityID == activity.id
          ) {
            model.selectedAIActivityID =
              model.selectedAIActivityID == activity.id ? nil : activity.id
          }
          if model.selectedAIActivityID == activity.id { AIActivityDetail(activity: activity) }
        }
      }
      .padding(12)
    }
    .scrollIndicators(.hidden)
  }

  private var ports: some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        ForEach(
          model.snapshot.services.flatMap { service in service.ports.map { (service, $0) } },
          id: \.1.id
        ) { item in
          HStack(spacing: 10) {
            RuntimeGlyph(runtime: item.0.runtime, serviceName: item.0.name, size: 34)
            VStack(alignment: .leading, spacing: 2) {
              Text(item.0.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
              Text("\(item.1.transport.rawValue.uppercased()) · \(item.1.address)")
                .font(.caption2)
                .foregroundStyle(WatchioPalette.secondaryText)
            }
            Spacer()
            Text(item.1.displayValue)
              .font(.system(.callout, design: .monospaced, weight: .semibold))
              .foregroundStyle(WatchioPalette.accent)
          }
          .padding(10)
          .background(
            WatchioPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous)
          )
          .accessibilityElement(children: .combine)
        }
      }
      .padding(12)
    }
    .scrollIndicators(.hidden)
    .overlay { if model.snapshot.services.allSatisfy(\.ports.isEmpty) { emptyState } }
  }

  private var health: some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        ForEach(model.snapshot.resourceAlerts) { alert in
          ResourceAlertHealthRow(alert: alert)
        }
        if !model.snapshot.resourceAlerts.isEmpty, !model.snapshot.sourceHealth.isEmpty {
          Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 3)
        }
        ForEach(model.snapshot.sourceHealth) { source in
          HStack(spacing: 10) {
            Image(
              systemName: source.state == .available
                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(source.state == .available ? WatchioPalette.accentSoft : .orange)
            VStack(alignment: .leading, spacing: 2) {
              Text(source.source.rawValue.capitalized).font(.system(size: 12, weight: .semibold))
              if let message = source.message {
                Text(message).font(.caption2).foregroundStyle(WatchioPalette.secondaryText)
              }
            }
            Spacer()
            Text(source.state.rawValue.capitalized)
              .font(.caption2)
              .foregroundStyle(WatchioPalette.secondaryText)
          }
          .padding(11)
          .background(
            WatchioPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      }
      .padding(12)
    }
    .scrollIndicators(.hidden)
  }

  private var emptyState: some View {
    ContentUnavailableView(
      "No development services",
      systemImage: "terminal",
      description: Text("Watchio only shows stable processes with strong development evidence.")
    )
  }

  private var aiEmptyState: some View {
    ContentUnavailableView(
      "No AI activity",
      systemImage: "sparkles",
      description: Text(
        "Watchio recognizes supported AI tools from process identity, project, TTY, and ancestry."
      )
    )
  }

  private var footer: some View {
    HStack {
      Circle()
        .fill(WatchioPalette.accentSoft)
        .frame(width: 5, height: 5)
        .shadow(color: WatchioPalette.accentSoft.opacity(0.6), radius: 4)
      Text("Updated \(model.snapshot.generatedAt, style: .relative)")
        .font(.caption2)
        .foregroundStyle(WatchioPalette.secondaryText)
      Spacer()
      Button {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
      } label: {
        Label("Settings", systemImage: "gearshape")
      }
      .accessibilityIdentifier("open-settings")
      .buttonStyle(.plain)
      Divider().overlay(Color.white.opacity(0.14)).frame(height: 14)
      Button("Quit") { NSApplication.shared.terminate(nil) }
        .buttonStyle(.plain)
        .keyboardShortcut("q", modifiers: .command)
    }
    .font(.system(size: 11, weight: .medium))
    .foregroundStyle(Color.white.opacity(0.78))
    .padding(13)
  }
}

private struct ResourceAlertHealthRow: View {
  let alert: ResourceAlert

  var body: some View {
    Link(destination: deepLink) {
      HStack(spacing: 10) {
        Image(systemName: alert.kind == .memory ? "memorychip.fill" : "bolt.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text(alert.subjectName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
          Text(alert.kind.displayName).font(.caption2).foregroundStyle(WatchioPalette.secondaryText)
        }
        Spacer()
        Text(value)
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
          .foregroundStyle(.orange)
      }
      .padding(11)
      .background(Color.orange.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.32), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("resource-alert-\(alert.id)")
  }

  private var value: String {
    switch alert.kind {
    case .memory: WatchioFormat.bytes(alert.memoryBytes)
    case .energy: WatchioFormat.cpu(alert.cpuPercent ?? 0)
    }
  }

  private var deepLink: URL {
    let host = alert.subjectKind == .aiActivity ? "ai" : "service"
    return URL(string: "watchio://\(host)/\(alert.subjectID)")!
  }
}

private struct AIActivityRow: View {
  let activity: DetectedAIActivity
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        AIToolGlyph(tool: activity.tool, size: 38)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(activity.tool.displayName)
              .font(.system(size: 13, weight: .semibold))
              .lineLimit(1)
            Circle()
              .fill(WatchioPalette.accentSoft)
              .frame(width: 5, height: 5)
              .shadow(color: WatchioPalette.accentSoft.opacity(0.55), radius: 3)
          }
          Text(contextLabel)
            .font(.system(size: 10))
            .foregroundStyle(WatchioPalette.secondaryText)
            .lineLimit(1)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 5) {
          HStack(spacing: 8) {
            Text(activity.host.displayName)
              .font(.system(size: 9, weight: .medium, design: .rounded))
              .foregroundStyle(.white.opacity(0.68))
              .padding(.horizontal, 7)
              .padding(.vertical, 4)
              .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            Text(WatchioFormat.uptime(activity))
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(WatchioPalette.secondaryText)
              .frame(width: 44, alignment: .trailing)
            Image(systemName: selected ? "chevron.up" : "chevron.down")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(WatchioPalette.tertiaryText)
          }
          HStack(spacing: 9) {
            AIResourceMetric(
              systemImage: "cpu", label: "CPU", value: WatchioFormat.cpu(activity.cpuPercent))
            AIResourceMetric(
              systemImage: "memorychip", label: "RAM",
              value: WatchioFormat.bytes(activity.memoryBytes))
          }
        }
      }
      .padding(10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selected ? Color.white.opacity(0.075) : WatchioPalette.card,
      in: RoundedRectangle(cornerRadius: 13, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .stroke(selected ? Color.white.opacity(0.13) : WatchioPalette.cardBorder, lineWidth: 1)
    }
    .accessibilityValue(
      "\(activity.tool.displayName), \(activity.host.displayName), CPU \(WatchioFormat.cpu(activity.cpuPercent)), RAM \(WatchioFormat.bytes(activity.memoryBytes))"
    )
    .accessibilityIdentifier("ai-activity-\(activity.id)")
  }

  private var contextLabel: String {
    let project = activity.projectPath ?? activity.projectName ?? "No project context"
    guard let tty = activity.tty else { return project }
    return "\(project) · \(tty)"
  }
}

private struct AIResourceMetric: View {
  let systemImage: String
  let label: String
  let value: String

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: systemImage)
        .font(.system(size: 8, weight: .medium))
      Text(value)
        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
    }
    .foregroundStyle(Color.white.opacity(0.58))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label) \(value)")
  }
}

private struct AIActivityDetail: View {
  @Environment(AppModel.self) private var model
  let activity: DetectedAIActivity
  @State private var isConfirmingStop = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
        detail("PID", String(activity.representativePID))
        detail("Processes", String(activity.processCount))
        detail("CPU (process tree)", WatchioFormat.cpu(activity.cpuPercent))
        detail("RAM (RSS process tree)", WatchioFormat.bytes(activity.memoryBytes))
        detail("Host", activity.host.displayName)
        detail("Confidence", "\(activity.confidence)%")
        GridRow {
          Text("Evidence").foregroundStyle(.secondary)
          Text(activity.evidence.map(\.displayName).joined(separator: " · ")).lineLimit(3)
        }
      }
      processControl(
        processID: activity.representativePID, processCount: activity.processCount,
        displayName: activity.tool.displayName)
    }
    .font(.caption)
    .foregroundStyle(.white.opacity(0.82))
    .padding(11)
    .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
    .padding(.horizontal, 4)
    .padding(.bottom, 4)
    .alert("Stop \(activity.tool.displayName) process tree?", isPresented: $isConfirmingStop) {
      Button("Cancel", role: .cancel) {}
      Button("Stop now", role: .destructive) {
        Task { await model.stopProcessTree(for: activity) }
      }
    } message: {
      Text(stopConfirmationMessage(processCount: activity.processCount))
    }
  }

  private func detail(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }

  private func processControl(
    processID: Int32, processCount: Int, displayName: String
  ) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "shield.lefthalf.filled")
        .foregroundStyle(.orange)
      Text("Verified tree · TERM, then KILL survivors")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Spacer()
      Button(role: .destructive) {
        isConfirmingStop = true
      } label: {
        if model.isStopping(processID: processID) {
          ProgressView().controlSize(.small)
        } else {
          Label("Stop tree…", systemImage: "power")
        }
      }
      .disabled(model.stoppingProcessID != nil)
      .accessibilityLabel("Stop the selected \(displayName) process tree")
      .accessibilityIdentifier("stop-ai-\(activity.id)")
    }
    .padding(.top, 2)
  }
}

private struct ServiceRow: View {
  let service: DetectedService
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        RuntimeGlyph(runtime: service.runtime, serviceName: service.name, size: 38)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(service.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Circle()
              .fill(WatchioPalette.accentSoft)
              .frame(width: 5, height: 5)
              .shadow(color: WatchioPalette.accentSoft.opacity(0.55), radius: 3)
          }
          Text(service.projectPath ?? service.projectName)
            .font(.system(size: 10))
            .foregroundStyle(WatchioPalette.secondaryText)
            .lineLimit(1)
        }
        Spacer()
        if let endpoint = service.ports.first {
          Text(endpoint.displayValue)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(WatchioPalette.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
              WatchioPalette.accent.opacity(0.085),
              in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        } else {
          Text("worker")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(WatchioPalette.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        }
        Text(WatchioFormat.uptime(service))
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(WatchioPalette.secondaryText)
          .frame(width: 44, alignment: .trailing)
        Image(systemName: selected ? "chevron.up" : "chevron.down")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(WatchioPalette.tertiaryText)
      }
      .padding(10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selected ? Color.white.opacity(0.075) : WatchioPalette.card,
      in: RoundedRectangle(cornerRadius: 13, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 13, style: .continuous)
        .stroke(selected ? Color.white.opacity(0.13) : WatchioPalette.cardBorder, lineWidth: 1)
    }
    .accessibilityValue(
      RuntimeGlyph.accessibilityName(for: service.runtime, serviceName: service.name)
    )
    .accessibilityIdentifier("service-\(service.id)")
  }
}

private struct ServiceDetail: View {
  @Environment(AppModel.self) private var model
  let service: DetectedService
  @State private var isConfirmingStop = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
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
      if let processID = service.representativePID, service.representativeStartedAt != nil {
        HStack(spacing: 8) {
          Image(systemName: "shield.lefthalf.filled").foregroundStyle(.orange)
          Text("Verified tree · TERM, then KILL survivors")
            .font(.caption2).foregroundStyle(.secondary)
          Spacer()
          Button(role: .destructive) {
            isConfirmingStop = true
          } label: {
            if model.isStopping(processID: processID) {
              ProgressView().controlSize(.small)
            } else {
              Label("Stop tree…", systemImage: "power")
            }
          }
          .disabled(model.stoppingProcessID != nil)
          .accessibilityLabel("Stop the selected \(service.name) process tree")
          .accessibilityIdentifier("stop-service-\(service.id)")
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.white.opacity(0.82))
    .padding(11)
    .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
    .padding(.horizontal, 4)
    .padding(.bottom, 4)
    .alert("Stop \(service.name) process tree?", isPresented: $isConfirmingStop) {
      Button("Cancel", role: .cancel) {}
      Button("Stop now", role: .destructive) {
        Task { await model.stopProcessTree(for: service) }
      }
    } message: {
      Text(stopConfirmationMessage(processCount: service.processCount))
    }
  }

  private func detail(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled)
    }
  }
}

private func stopConfirmationMessage(processCount: Int) -> String {
  "This row currently groups \(processCount) processes. Watchio will resolve the selected PID tree again, freeze and re-verify its same-user members, send SIGTERM deepest-first, wait up to 5 seconds, then SIGKILL only verified survivors. This cannot be undone."
}
