import SwiftUI

extension StatusTone {
    var color: Color {
        switch self {
        case .waiting: .gray
        case .ready: .orange
        case .active: .green
        case .paused: .blue
        case .error: .red
        }
    }
}

enum Metrics {
    static let cornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 12
    static let cardFillOpacity = 0.06
    static let strokeOpacity = 0.15
    static let hairline: CGFloat = 1
    static let emphasisBorder: CGFloat = 1.5
    static let bannerPadding: CGFloat = 10
    static let glassTintOpacity = 0.22
    static let glassGroupSpacing: CGFloat = 4
}

/// Which look the surfaces (cards, banners, buttons) take. `current` is the one place that decides.
enum SurfaceStyle: Equatable, Sendable {
    /// Liquid Glass, macOS 26 and later.
    case glass
    /// Flat translucent fills drawn in SwiftUI, for older systems and for `ImageRenderer`.
    case classic

    static let firstGlassMajorVersion = 26

    /// Whether this build has the glass APIs: Xcode 26 ships Swift 6.2.
    static var sdkHasGlass: Bool {
        #if compiler(>=6.2)
            true
        #else
            false
        #endif
    }

    static func resolve(osMajorVersion: Int, sdkHasGlass: Bool) -> SurfaceStyle {
        sdkHasGlass && osMajorVersion >= firstGlassMajorVersion ? .glass : .classic
    }

    static let current: SurfaceStyle = resolve(
        osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion, sdkHasGlass: sdkHasGlass)
}

private struct SurfaceStyleKey: EnvironmentKey {
    static let defaultValue = SurfaceStyle.current
}

extension EnvironmentValues {
    /// Screenshots set `.classic`: `ImageRenderer` cannot draw real glass.
    var surfaceStyle: SurfaceStyle {
        get { self[SurfaceStyleKey.self] }
        set { self[SurfaceStyleKey.self] = newValue }
    }
}

// Every use of the macOS 26 glass APIs, and every `#available` check, lives in this section.

#if compiler(>=6.2)
    @available(macOS 26, *)
    extension View {
        fileprivate func glassSurface(tint: Color?) -> some View {
            let glass = tint.map { Glass.regular.tint($0.opacity(Metrics.glassTintOpacity)) } ?? Glass.regular
            return glassEffect(
                glass, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
    }
#endif

private struct CardSurface: ViewModifier {
    let emphasis: Color?
    @Environment(\.surfaceStyle) private var style

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *), style == .glass {
                padded(content).glassSurface(tint: emphasis)
            } else {
                classic(content)
            }
        #else
            classic(content)
        #endif
    }

    private func padded(_ content: Content) -> some View {
        content.padding(Metrics.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func classic(_ content: Content) -> some View {
        let border = emphasis ?? Color.primary.opacity(Metrics.strokeOpacity)
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
        return padded(content)
            .background(shape.fill(Color.primary.opacity(Metrics.cardFillOpacity)))
            .overlay(shape.stroke(border, lineWidth: emphasis == nil ? Metrics.hairline : Metrics.emphasisBorder))
    }
}

private struct BannerSurface: ViewModifier {
    let tint: Color
    let classicPadding: EdgeInsets
    @Environment(\.surfaceStyle) private var style

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *), style == .glass {
                content.padding(Metrics.bannerPadding).frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(tint: tint)
            } else {
                content.padding(classicPadding)
            }
        #else
            content.padding(classicPadding)
        #endif
    }
}

private struct ButtonSurface: ViewModifier {
    let prominent: Bool
    @Environment(\.surfaceStyle) private var style

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *), style == .glass {
                if prominent {
                    content.buttonStyle(.glassProminent)
                } else {
                    content.buttonStyle(.glass)
                }
            } else {
                classic(content)
            }
        #else
            classic(content)
        #endif
    }

    @ViewBuilder
    private func classic(_ content: Content) -> some View {
        if prominent {
            content.buttonStyle(PillButtonStyle())
        } else {
            content.buttonStyle(SecondaryButtonStyle())
        }
    }
}

/// Lets glass elements that sit together share one sampling region; a plain pass-through otherwise.
struct GlassGroup<Content: View>: View {
    private let content: Content
    @Environment(\.surfaceStyle) private var style

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        #if compiler(>=6.2)
            if #available(macOS 26, *), style == .glass {
                GlassEffectContainer(spacing: Metrics.glassGroupSpacing) { content }
            } else {
                content
            }
        #else
            content
        #endif
    }
}

extension View {
    /// A panel. `emphasis` marks a card that must stand out: an outline, or a glass tint.
    func ghCard(emphasis: Color? = nil) -> some View {
        modifier(CardSurface(emphasis: emphasis))
    }

    /// A tinted glass strip; on older systems the content stays bare, with only `classicPadding`.
    func ghBanner(tint: Color, classicPadding: EdgeInsets = EdgeInsets()) -> some View {
        modifier(BannerSurface(tint: tint, classicPadding: classicPadding))
    }

    func ghButtonStyle(prominent: Bool) -> some View {
        modifier(ButtonSurface(prominent: prominent))
    }
}

struct Card<Content: View>: View {
    private let emphasis: Color?
    private let content: Content

    init(emphasis: Color? = nil, @ViewBuilder content: () -> Content) {
        self.emphasis = emphasis
        self.content = content()
    }

    var body: some View {
        content.ghCard(emphasis: emphasis)
    }
}

struct StatusBadge: View {
    let status: StatusPresentation
    var size: CGFloat = 34

    private static let fillOpacity = 0.18
    private static let symbolScale = 0.5

    var body: some View {
        ZStack {
            Circle().fill(status.tone.color.opacity(Self.fillOpacity))
            Image(systemName: status.symbolName)
                .font(.system(size: size * Self.symbolScale, weight: .medium))
                .foregroundColor(status.tone.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Drawn in SwiftUI only: AppKit-backed controls render as placeholders in `ImageRenderer` screenshots.
struct PillButtonStyle: ButtonStyle {
    private static let pressedOpacity = 0.75

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accentColor))
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
    }
}

/// A quieter button next to a primary one.
struct SecondaryButtonStyle: ButtonStyle {
    private static let pressedOpacity = 0.6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(Metrics.cardFillOpacity)))
            .overlay(Capsule().stroke(Color.primary.opacity(Metrics.strokeOpacity * 2), lineWidth: Metrics.hairline))
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
    }
}

/// Coloured icon, primary text: coloured text does not reach AA contrast in light mode.
struct NoticeLabel: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundColor(color).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
