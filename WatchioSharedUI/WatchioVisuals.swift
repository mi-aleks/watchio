import SwiftUI
import WatchioModels

enum WatchioPalette {
  static let accent = Color(red: 0.73, green: 0.96, blue: 0.46)
  static let accentSoft = Color(red: 0.45, green: 0.82, blue: 0.58)
  static let surfaceTop = Color(red: 0.15, green: 0.17, blue: 0.15)
  static let surfaceBottom = Color(red: 0.065, green: 0.075, blue: 0.068)
  static let card = Color.white.opacity(0.045)
  static let cardBorder = Color.white.opacity(0.075)
  static let secondaryText = Color.white.opacity(0.52)
  static let tertiaryText = Color.white.opacity(0.34)
}

struct WatchioSurface: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [WatchioPalette.surfaceTop, WatchioPalette.surfaceBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      RadialGradient(
        colors: [WatchioPalette.accentSoft.opacity(0.14), .clear],
        center: .topLeading,
        startRadius: 0,
        endRadius: 330
      )
    }
  }
}

struct WatchioMark: View {
  var compact = false

  var body: some View {
    Text("w:")
      .font(.system(size: compact ? 11 : 13, weight: .black, design: .monospaced))
      .tracking(-1)
      .foregroundStyle(WatchioPalette.accent)
      .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
      .background(
        WatchioPalette.accent.opacity(0.1),
        in: RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
          .stroke(WatchioPalette.accent.opacity(0.2), lineWidth: 1)
      }
      .accessibilityLabel("Watchio")
  }
}

struct AIToolGlyph: View {
  let tool: AIToolKind
  var size: CGFloat = 34

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
        .fill(tint.opacity(0.13))
      RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
        .stroke(tint.opacity(0.25), lineWidth: 1)
      Image(systemName: symbol)
        .symbolRenderingMode(.monochrome)
        .font(.system(size: size * 0.43, weight: .semibold))
        .foregroundStyle(tint)
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(tool.displayName) AI tool")
    .accessibilityIdentifier("ai-icon-\(tool.rawValue)")
  }

  private var symbol: String {
    switch tool {
    case .codex: "cube.transparent.fill"
    case .claude: "asterisk"
    case .gemini: "sparkles"
    case .aider: "wand.and.stars"
    case .openCode: "chevron.left.forwardslash.chevron.right"
    case .goose: "bird.fill"
    case .copilot: "person.2.fill"
    case .cursor: "cursorarrow.rays"
    }
  }

  private var tint: Color {
    switch tool {
    case .codex: WatchioPalette.accent
    case .claude: Color(red: 0.95, green: 0.57, blue: 0.36)
    case .gemini: Color(red: 0.48, green: 0.68, blue: 0.98)
    case .aider: Color(red: 0.76, green: 0.59, blue: 0.98)
    case .openCode: Color(red: 0.43, green: 0.87, blue: 0.58)
    case .goose: Color(red: 0.96, green: 0.7, blue: 0.36)
    case .copilot: Color.white.opacity(0.76)
    case .cursor: Color(red: 0.38, green: 0.82, blue: 0.91)
    }
  }
}

struct RuntimeGlyph: View {
  let runtime: RuntimeKind
  var serviceName = ""
  var size: CGFloat = 34

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
        .fill(tint.opacity(0.13))
      RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
        .stroke(tint.opacity(0.25), lineWidth: 1)
      glyph
        .frame(width: size * 0.62, height: size * 0.62)
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityName)
    .accessibilityIdentifier("service-icon-\(isDatabase ? "database" : runtime.rawValue)")
  }

  @ViewBuilder private var glyph: some View {
    if isDatabase {
      Image(systemName: "cylinder.fill")
        .font(.system(size: size * 0.43, weight: .semibold))
        .foregroundStyle(tint)
    } else {
      switch runtime {
      case .node:
        ZStack {
          Hexagon()
            .stroke(tint, lineWidth: max(1.2, size * 0.045))
          Text("JS")
            .font(.system(size: size * 0.24, weight: .black, design: .rounded))
            .foregroundStyle(tint)
        }
      case .go:
        GoGlyph(color: tint)
      case .python:
        PythonGlyph()
      case .docker:
        DockerGlyph(color: tint)
      case .bun:
        BunGlyph(color: tint)
      case .deno:
        DenoGlyph(color: tint)
      case .generic:
        Image(systemName: "terminal.fill")
          .font(.system(size: size * 0.38, weight: .semibold))
          .foregroundStyle(tint)
      }
    }
  }

  private var tint: Color {
    if isDatabase { return Color(red: 0.96, green: 0.68, blue: 0.35) }
    switch runtime {
    case .node: return Color(red: 0.43, green: 0.87, blue: 0.58)
    case .bun: return Color(red: 0.79, green: 0.69, blue: 0.98)
    case .deno: return Color(red: 0.76, green: 0.86, blue: 0.72)
    case .go: return Color(red: 0.38, green: 0.82, blue: 0.91)
    case .python: return Color(red: 0.39, green: 0.69, blue: 0.93)
    case .docker: return Color(red: 0.42, green: 0.61, blue: 0.98)
    case .generic: return WatchioPalette.secondaryText
    }
  }

  private var accessibilityName: String {
    Self.accessibilityName(for: runtime, serviceName: serviceName)
  }

  private var isDatabase: Bool {
    Self.isDatabase(runtime: runtime, serviceName: serviceName)
  }

  static func accessibilityName(for runtime: RuntimeKind, serviceName: String) -> String {
    isDatabase(runtime: runtime, serviceName: serviceName)
      ? "Database icon" : "\(runtime.displayName) icon"
  }

  private static func isDatabase(runtime: RuntimeKind, serviceName: String) -> Bool {
    guard runtime == .docker else { return false }
    let tokens = serviceName.lowercased().split { !$0.isLetter && !$0.isNumber }
    let databaseTokens: Set<Substring> = [
      "cockroach", "database", "db", "mariadb", "mongo", "mongodb", "mysql", "postgres",
      "postgresql", "redis", "sqlite",
    ]
    return !databaseTokens.isDisjoint(with: tokens)
  }
}

private struct Hexagon: Shape {
  func path(in rect: CGRect) -> Path {
    let points = [
      CGPoint(x: rect.midX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25),
      CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.25),
      CGPoint(x: rect.midX, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.25),
      CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25),
    ]
    var path = Path()
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
  }
}

private struct GoGlyph: View {
  let color: Color

  var body: some View {
    HStack(spacing: 1.5) {
      VStack(alignment: .trailing, spacing: 2) {
        Capsule().fill(color.opacity(0.65)).frame(width: 5, height: 1.5)
        Capsule().fill(color).frame(width: 8, height: 1.5)
        Capsule().fill(color.opacity(0.65)).frame(width: 5, height: 1.5)
      }
      Text("GO")
        .font(.system(size: 8.5, weight: .black, design: .rounded))
        .italic()
        .foregroundStyle(color)
    }
  }
}

private struct PythonGlyph: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color(red: 0.35, green: 0.67, blue: 0.9))
        .frame(width: 13, height: 9)
        .offset(x: -2.6, y: -3.2)
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Color(red: 0.98, green: 0.78, blue: 0.3))
        .frame(width: 13, height: 9)
        .offset(x: 2.6, y: 3.2)
      Circle().fill(WatchioPalette.surfaceBottom).frame(width: 1.8, height: 1.8)
        .offset(x: -4.6, y: -4.5)
      Circle().fill(WatchioPalette.surfaceBottom).frame(width: 1.8, height: 1.8)
        .offset(x: 4.6, y: 4.5)
    }
  }
}

private struct DockerGlyph: View {
  let color: Color

  var body: some View {
    VStack(spacing: 1.5) {
      HStack(alignment: .bottom, spacing: 1.5) {
        Color.clear.frame(width: 3.5, height: 3.5)
        block
        Color.clear.frame(width: 3.5, height: 3.5)
      }
      HStack(spacing: 1.5) {
        block
        block
        block
        block
      }
      Capsule().fill(color).frame(width: 18, height: 3)
    }
  }

  private var block: some View {
    RoundedRectangle(cornerRadius: 0.8).fill(color).frame(width: 3.5, height: 3.5)
  }
}

private struct BunGlyph: View {
  let color: Color

  var body: some View {
    ZStack {
      Ellipse().stroke(color, lineWidth: 1.5).frame(width: 17, height: 14)
      HStack(spacing: 5) {
        Circle().fill(color).frame(width: 1.8, height: 1.8)
        Circle().fill(color).frame(width: 1.8, height: 1.8)
      }
      Capsule().fill(color.opacity(0.7)).frame(width: 6, height: 1.2).offset(y: 4)
    }
  }
}

private struct DenoGlyph: View {
  let color: Color

  var body: some View {
    ZStack {
      Circle().stroke(color, lineWidth: 1.5)
      Circle().fill(color).frame(width: 3, height: 3).offset(x: 3, y: -3)
      Capsule().fill(color.opacity(0.8)).frame(width: 8, height: 1.4).rotationEffect(.degrees(-35))
        .offset(x: -2, y: 3)
    }
  }
}
