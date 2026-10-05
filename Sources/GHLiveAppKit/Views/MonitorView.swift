import GuitarInput
import SwiftUI

public struct MonitorView: View {
    public static let width: CGFloat = 440

    private let monitor: MonitorPresentation

    public init(monitor: MonitorPresentation) {
        self.monitor = monitor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHeader
            Card {
                VStack(spacing: 16) {
                    fretBoard
                    HStack(alignment: .top, spacing: 20) {
                        strumBar
                        faceButtons
                        dpad
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    whammyMeter
                    tiltMeter
                    Text("A key is sent when the bar crosses the line. Adjust in Settings.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            keysBeingSent
        }
        .padding(20)
        .frame(width: Self.width)
    }

    // MARK: Header

    private var statusHeader: some View {
        HStack(spacing: 10) {
            StatusBadge(status: monitor.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.status.headline).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = monitor.status.detail {
                    Text(detail).font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Buttons

    private var fretBoard: some View {
        VStack(spacing: 10) {
            fretRow([.black1, .black2, .black3], isBlack: true)
            fretRow([.white1, .white2, .white3], isBlack: false)
        }
    }

    private func fretRow(_ controls: [Control], isBlack: Bool) -> some View {
        HStack(spacing: 14) {
            ForEach(controls, id: \.self) { control in
                FretView(
                    name: control.friendlyName,
                    keyLabel: monitor.keyLabel(for: control),
                    isBlack: isBlack,
                    isPressed: monitor.isActive(control)
                )
            }
        }
    }

    private var strumBar: some View {
        VStack(spacing: 6) {
            PadView(
                name: Control.strumUp.friendlyName, symbol: "chevron.up", width: 64,
                isPressed: monitor.isActive(.strumUp))
            PadView(
                name: Control.strumDown.friendlyName, symbol: "chevron.down", width: 64,
                isPressed: monitor.isActive(.strumDown))
        }
    }

    private var faceButtons: some View {
        VStack(spacing: 6) {
            PadView(
                name: Control.heroPower.friendlyName, title: "Hero Power", width: 96,
                isPressed: monitor.isActive(.heroPower))
            HStack(spacing: 6) {
                PadView(
                    name: Control.pause.friendlyName, title: "Pause", width: 56, isPressed: monitor.isActive(.pause))
                PadView(name: Control.ghtv.friendlyName, title: "GHTV", width: 56, isPressed: monitor.isActive(.ghtv))
            }
        }
    }

    private var dpad: some View {
        VStack(spacing: 3) {
            PadView(
                name: Control.dpadUp.friendlyName, symbol: "arrowtriangle.up.fill", width: 28, height: 22,
                isPressed: monitor.isActive(.dpadUp))
            HStack(spacing: 3) {
                PadView(
                    name: Control.dpadLeft.friendlyName, symbol: "arrowtriangle.left.fill", width: 28, height: 22,
                    isPressed: monitor.isActive(.dpadLeft))
                Color.clear.frame(width: 28, height: 22)
                PadView(
                    name: Control.dpadRight.friendlyName, symbol: "arrowtriangle.right.fill", width: 28, height: 22,
                    isPressed: monitor.isActive(.dpadRight))
            }
            PadView(
                name: Control.dpadDown.friendlyName, symbol: "arrowtriangle.down.fill", width: 28, height: 22,
                isPressed: monitor.isActive(.dpadDown))
        }
    }

    // MARK: Analog

    private var whammyMeter: some View {
        MeterView(
            title: "Whammy bar",
            level: monitor.whammyLevel,
            thresholdLevel: monitor.thresholds.whammy,
            isEngaged: monitor.isActive(.whammy),
            valueText: String(format: "%.2f", monitor.whammyLevel),
            thresholdText: String(format: "%.2f", monitor.thresholds.whammy)
        )
    }

    private var tiltMeter: some View {
        MeterView(
            title: "Tilt",
            level: monitor.tiltLevel,
            thresholdLevel: monitor.tiltThresholdLevel,
            isEngaged: monitor.isActive(.tilt),
            valueText: String(monitor.state.map { Int($0.tilt) } ?? 0),
            thresholdText: String(monitor.thresholds.tilt)
        )
    }

    // MARK: Keys

    private var keysBeingSent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KEYS BEING SENT").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            HStack(spacing: 6) {
                if monitor.keysBeingSent.isEmpty {
                    Text(monitor.isPaused ? "None, paused" : "None").foregroundColor(.secondary)
                } else {
                    ForEach(monitor.keysBeingSent, id: \.self) { label in
                        Text(label)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                            .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keys being sent")
        .accessibilityValue(monitor.keysBeingSent.isEmpty ? "None" : monitor.keysBeingSent.joined(separator: ", "))
    }
}

// MARK: - Components

private enum Glow {
    static let radius: CGFloat = 8
    static let opacity = 0.7
}

private struct FretView: View {
    let name: String
    let keyLabel: String?
    let isBlack: Bool
    let isPressed: Bool

    @Environment(\.colorScheme) private var colorScheme

    private static let size: CGFloat = 54
    private static let pressedRingWidth: CGFloat = 5
    private static let whiteInDarkMode = 0.9
    private static let whiteInLightMode = 0.96

    var body: some View {
        ZStack {
            Circle().fill(fill)
            if isPressed {
                // The ring keeps the row identifiable: a pressed black fret stays dark-ringed, a white one light.
                Circle().strokeBorder(ringColor, lineWidth: Self.pressedRingWidth)
            }
            Circle().stroke(isPressed ? Color.accentColor : Color.primary.opacity(0.4), lineWidth: 2)
            if let keyLabel {
                Text(keyLabel)
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundColor(labelColor)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .shadow(color: isPressed ? Color.accentColor.opacity(Glow.opacity) : .clear, radius: Glow.radius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(isPressed ? "Pressed" : "Released")
    }

    private var fill: Color {
        if isPressed { return .accentColor }
        return isBlack ? Color(white: 0.12) : Color(white: whiteLevel)
    }

    private var ringColor: Color {
        isBlack ? Color(white: 0.1) : Color(white: whiteLevel)
    }

    private var whiteLevel: Double {
        colorScheme == .dark ? Self.whiteInDarkMode : Self.whiteInLightMode
    }

    private var labelColor: Color {
        if isPressed { return .white }
        return isBlack ? Color(white: 0.85) : Color(white: 0.25)
    }
}

private struct PadView: View {
    let name: String
    var title: String?
    var symbol: String?
    var width: CGFloat
    var height: CGFloat = 28
    let isPressed: Bool

    init(
        name: String, title: String? = nil, symbol: String? = nil, width: CGFloat, height: CGFloat = 28,
        isPressed: Bool
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.width = width
        self.height = height
        self.isPressed = isPressed
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isPressed ? Color.accentColor : Color.primary.opacity(0.1))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isPressed ? Color.accentColor : Color.primary.opacity(0.25), lineWidth: 1)
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            }
            if let title {
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .foregroundColor(isPressed ? .white : .primary)
        .frame(width: width, height: height)
        .shadow(color: isPressed ? Color.accentColor.opacity(Glow.opacity) : .clear, radius: Glow.radius / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(isPressed ? "Pressed" : "Released")
    }
}

/// A bar from 0 to 1 with a marker where the control engages.
private struct MeterView: View {
    let title: String
    let level: Double
    let thresholdLevel: Double
    let isEngaged: Bool
    let valueText: String
    let thresholdText: String

    private static let barHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).fontWeight(.medium)
                // Always laid out, so the row does not shift when the control engages.
                Text("ON")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.3)))
                    .opacity(isEngaged ? 1 : 0)
                    .accessibilityHidden(true)
                Spacer()
                Text(valueText).monospacedDigit().fontWeight(.semibold)
                Text("/ trigger at \(thresholdText)").font(.caption).foregroundColor(.secondary)
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(isEngaged ? Color.green : Color.accentColor)
                        .frame(width: max(width * min(max(level, 0), 1), Self.barHeight))
                        .opacity(level > 0 ? 1 : 0.35)
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: Self.barHeight + 8)
                        .offset(x: width * min(max(thresholdLevel, 0), 1) - 1)
                }
                .frame(height: Self.barHeight)
                .frame(maxHeight: .infinity)
            }
            .frame(height: Self.barHeight + 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(valueText), triggers at \(thresholdText), \(isEngaged ? "on" : "off")")
    }
}
