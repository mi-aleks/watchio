import SwiftUI
import WatchioModels

struct RuntimeBadge: View {
  let runtime: RuntimeKind

  var body: some View {
    RuntimeGlyph(runtime: runtime, size: 30)
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
