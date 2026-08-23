import AppKit
import SwiftUI
@preconcurrency import UserNotifications

@MainActor
final class DemoWindowAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate
{
  private var demoWindow: NSWindow?
  private var demoModel: AppModel?
  private var deepLinkWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    guard ProcessInfo.processInfo.arguments.contains("--screenshot-mode") else { return }
    let arguments = ProcessInfo.processInfo.arguments
    let showOnboarding = arguments.contains("--show-onboarding")
    let model =
      arguments.contains("--live-data")
      ? WatchioRuntime.model : AppModel(demoMode: true, showOnboarding: showOnboarding)
    if arguments.contains("--ai-mode") { model.selectedMode = .ai }
    if arguments.contains("--health-mode") { model.selectedMode = .health }
    let controller = NSHostingController(rootView: MenuBarContentView().environment(model))
    let window = NSWindow(contentViewController: controller)
    window.title = "Watchio"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask = [.titled, .closable, .fullSizeContentView]
    window.setContentSize(NSSize(width: 420, height: showOnboarding ? 620 : 500))
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
    demoModel = model
    demoWindow = window
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    let model = WatchioRuntime.model
    model.handleDeepLink(url)
    presentDeepLinkWindow(model: model)
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let urlString = response.notification.request.content.userInfo["watchioURL"] as? String
    completionHandler()
    guard let urlString, let url = URL(string: urlString) else { return }
    Task { @MainActor in
      let model = WatchioRuntime.model
      model.handleDeepLink(url)
      presentDeepLinkWindow(model: model)
    }
  }

  private func presentDeepLinkWindow(model: AppModel) {
    let window: NSWindow
    if let deepLinkWindow {
      window = deepLinkWindow
    } else {
      let controller = NSHostingController(rootView: MenuBarContentView().environment(model))
      let created = NSWindow(contentViewController: controller)
      created.title = "Watchio"
      created.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
      created.setContentSize(NSSize(width: 420, height: 500))
      created.isReleasedWhenClosed = false
      created.center()
      deepLinkWindow = created
      window = created
    }
    window.makeKeyAndOrderFront(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
