import SwiftUI
import WatchioModels

struct RuntimeBadge: View {
  let runtime: RuntimeKind

  var body: some View {
    Text(runtime.badge)
      .font(.system(size: 10, weight: .bold, design: .monospaced))
      .foregroundStyle(color)
      .frame(width: 30, height: 22)
      .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
      .accessibilityLabel(runtime.displayName)
  }

  private var color: Color {
    switch runtime {
    case .node: .green
    case .bun: .orange
    case .deno: .primary
    case .go: .cyan
    case .python: .blue
    case .docker: .indigo
    case .generic: .secondary
    }
  }
}

enum WatchioFormat {
  static func uptime(_ service: DetectedService, now: Date = .now) -> String {
    guard let seconds = service.uptime(referenceDate: now) else { return "—" }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = seconds >= 3_600 ? [.hour, .minute] : [.minute, .second]
    formatter.maximumUnitCount = 2
    return formatter.string(from: seconds) ?? "—"
  }

  static func bytes(_ bytes: UInt64?) -> String {
    guard let bytes else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
  }
}
