import SwiftUI

@main
struct WatchioApp: App {
  @NSApplicationDelegateAdaptor(DemoWindowAppDelegate.self) private var appDelegate
  @State private var model = WatchioRuntime.model

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView()
        .environment(model)
    } label: {
      MenuBarStatusLabel(model: model)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environment(model)
    }
  }
}

private struct MenuBarStatusLabel: View {
  let model: AppModel

  private var needsAttention: Bool {
    !model.snapshot.resourceAlerts.isEmpty || model.snapshot.collectorState == .degraded
  }

  private var statusDescription: String {
    if !model.snapshot.resourceAlerts.isEmpty {
      let count = model.snapshot.resourceAlerts.count
      return "\(count) resource \(count == 1 ? "alert" : "alerts")"
    }
    if model.snapshot.collectorState == .degraded { return "collector degraded" }
    return "healthy"
  }

  var body: some View {
    HStack(spacing: 4) {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "terminal")
          .font(.system(size: 13, weight: .medium))
        if needsAttention {
          Circle()
            .fill(.orange)
            .frame(width: 5, height: 5)
            .overlay { Circle().stroke(Color.black.opacity(0.45), lineWidth: 0.5) }
            .offset(x: 2, y: -1)
            .accessibilityHidden(true)
        }
      }
      Text(model.menuBarTitle)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Watchio, \(model.snapshot.services.count) active services and \(model.snapshot.aiActivities.count) AI activities, \(statusDescription)"
    )
  }
}
