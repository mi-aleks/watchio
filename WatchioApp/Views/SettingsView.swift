import AppKit
import ServiceManagement
import SwiftUI
import WatchioModels

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var newIncludeRule = ""
  @State private var newIgnoreRule = ""

  var body: some View {
    @Bindable var model = model
    TabView {
      general.tabItem { Label("General", systemImage: "gear") }
      detection.tabItem { Label("Detection", systemImage: "scope") }
      review.tabItem { Label("Review", systemImage: "checklist") }
      widget.tabItem { Label("Widget", systemImage: "rectangle.grid.2x2") }
      privacy.tabItem { Label("Privacy", systemImage: "hand.raised") }
      about.tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 640, height: 480)
    .onOpenURL { model.handleDeepLink($0) }
    .alert(
      "Watchio",
      isPresented: Binding(
        get: { model.lastError != nil },
        set: { if !$0 { model.lastError = nil } }
      )
    ) {
      Button("OK") { model.lastError = nil }
    } message: {
      Text(model.lastError ?? "")
    }
  }

  private var general: some View {
    Form {
      Toggle(
        "Launch Watchio at login",
        isOn: Binding(
          get: { model.launchAtLogin },
          set: { enabled in model.setLaunchAtLogin(enabled) }
        )
      )
      .accessibilityIdentifier("launch-at-login")
      Picker(
        "Scan interval",
        selection: Binding(
          get: { model.preferences.scanInterval },
          set: {
            model.preferences.scanInterval = $0
            model.savePreferences()
          }
        )
      ) {
        Text("5 seconds").tag(5.0)
        Text("10 seconds").tag(10.0)
        Text("30 seconds").tag(30.0)
      }
      Text(
        "Watchio collects only while the menu bar app is running. It never installs a LaunchAgent."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .padding()
  }

  private var detection: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        GroupBox("Project roots") {
          List {
            ForEach(model.preferences.projectRoots, id: \.self) { path in
              HStack {
                Image(systemName: "folder")
                Text(displayPath(path)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button {
                  model.removeProjectRoot(path)
                } label: {
                  Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain).accessibilityLabel("Remove \(displayPath(path))")
              }
            }
          }
          .frame(height: 130)
          HStack {
            Button("Add Folder…", action: chooseRoot)
            Spacer()
            Text("Only these roots are considered project evidence.").font(.caption)
              .foregroundStyle(
                .secondary)
          }
          .padding(8)
        }

        GroupBox("Runtimes") {
          HStack {
            ForEach(RuntimeKind.allCases.filter { $0 != .generic }, id: \.self) { runtime in
              Toggle(runtime.displayName, isOn: runtimeBinding(runtime)).toggleStyle(.checkbox)
            }
          }
          .padding(8)
        }

        GroupBox("Rules") {
          VStack(alignment: .leading, spacing: 12) {
            Text(
              "Include and ignore rules use shell-style globs against executable and project paths."
            )
            .font(.caption).foregroundStyle(.secondary)
            ruleEditor(
              title: "Always include", rules: model.preferences.includeRules,
              draft: $newIncludeRule, accessibilityID: "include-rule",
              add: {
                model.addIncludeRule(newIncludeRule)
                newIncludeRule = ""
              },
              remove: model.removeIncludeRule
            )
            Divider()
            ruleEditor(
              title: "Ignore", rules: model.preferences.ignoreRules,
              draft: $newIgnoreRule, accessibilityID: "ignore-rule",
              add: {
                model.addIgnoreRule(newIgnoreRule)
                newIgnoreRule = ""
              },
              remove: model.removeIgnoreRule
            )
          }
          .padding(8)
        }
      }
      .padding()
    }
  }

  private func ruleEditor(
    title: String,
    rules: [String],
    draft: Binding<String>,
    accessibilityID: String,
    add: @escaping () -> Void,
    remove: @escaping (String) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).fontWeight(.medium)
      ForEach(rules, id: \.self) { rule in
        HStack {
          Text(rule).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
          Spacer()
          Button {
            remove(rule)
          } label: {
            Image(systemName: "minus.circle")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove \(rule)")
        }
      }
      HStack {
        TextField("Example: */node_modules/*", text: draft)
          .textFieldStyle(.roundedBorder)
          .onSubmit(add)
          .accessibilityIdentifier(accessibilityID)
        Button("Add", action: add)
          .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
  }

  private var review: some View {
    Group {
      if model.snapshot.reviewSuggestions.isEmpty {
        ContentUnavailableView(
          "Nothing to review", systemImage: "checkmark.seal",
          description: Text(
            "Processes scoring 40–59 appear here without being added to the widget.")
        )
      } else {
        List(model.snapshot.reviewSuggestions) { suggestion in
          HStack {
            RuntimeBadge(runtime: suggestion.service.runtime)
            VStack(alignment: .leading) {
              Text(suggestion.service.name)
              Text("Confidence \(suggestion.service.confidence)%")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(suggestion.service.evidence.map(\.displayName).joined(separator: " · "))
              .font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
        }
      }
    }
    .padding()
  }

  private var widget: some View {
    Form {
      LabeledContent("Families", value: "Small, Medium, Large")
      LabeledContent("Configuration", value: "Services / Ports / Health, all or one project")
      LabeledContent("Freshness") { Text("Offline after 30 seconds").foregroundStyle(.secondary) }
      Text(
        "macOS controls widget refresh timing. Watchio requests refreshes for material changes and a throttled freshness heartbeat."
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .padding()
  }

  private var privacy: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Fully local", systemImage: "checkmark.shield.fill").font(.title2).foregroundStyle(
        .green)
      promise("No telemetry, accounts, analytics, or network requests")
      promise("No root access, privilege prompts, or process-changing actions")
      promise("No environment variables or command arguments collected")
      promise("Only the latest redacted snapshot is stored; no history")
      promise("Project paths inside your home directory are shortened to ~")
      Spacer()
      Link(
        "Read PRIVACY.md",
        destination: URL(string: "https://github.com/mi-aleks/watchio/blob/main/PRIVACY.md")!)
    }
    .padding(28)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var about: some View {
    VStack(spacing: 12) {
      Text("w:").font(.system(size: 58, weight: .black, design: .monospaced)).foregroundStyle(.tint)
      Text("Watchio").font(.title.bold())
      Text("0.1.0-alpha.1").foregroundStyle(.secondary)
      Text("An open-source development service observer for macOS.")
      HStack {
        Link("GitHub", destination: URL(string: "https://github.com/mi-aleks/watchio")!)
        Link(
          "MIT License",
          destination: URL(string: "https://github.com/mi-aleks/watchio/blob/main/LICENSE")!)
      }
      Spacer()
      Text("Made locally. No telemetry.").font(.caption).foregroundStyle(.secondary)
    }
    .padding(28)
  }

  private func runtimeBinding(_ runtime: RuntimeKind) -> Binding<Bool> {
    Binding(
      get: { model.preferences.enabledRuntimes.contains(runtime) },
      set: { enabled in
        if enabled {
          model.preferences.enabledRuntimes.insert(runtime)
        } else {
          model.preferences.enabledRuntimes.remove(runtime)
        }
        model.savePreferences()
      }
    )
  }

  private func chooseRoot() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Add Project Root"
    if panel.runModal() == .OK, let path = panel.url?.path { model.addProjectRoot(path) }
  }

  private func displayPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }

  private func promise(_ text: String) -> some View {
    Label(text, systemImage: "checkmark.circle").foregroundStyle(.primary)
  }
}
