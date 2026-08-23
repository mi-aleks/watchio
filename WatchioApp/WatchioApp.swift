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
      Label(
        model.menuBarTitle,
        systemImage: !model.snapshot.resourceAlerts.isEmpty
          ? "exclamationmark.triangle.fill"
          : (model.snapshot.collectorState == .degraded ? "exclamationmark.circle" : "terminal")
      )
      .accessibilityLabel(
        "Watchio, \(model.snapshot.services.count) active services and \(model.snapshot.aiActivities.count) AI activities"
      )
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environment(model)
    }
  }
}
