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
        systemImage: model.snapshot.collectorState == .degraded
          ? "exclamationmark.circle" : "terminal"
      )
      .accessibilityLabel("Watchio, \(model.snapshot.services.count) active services")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environment(model)
    }
  }
}
