import AppKit
import GuitarInput
import KeyMapping
import SwiftUI

public struct SettingsView: View {
    public static let width: CGFloat = 780

    @ObservedObject private var model: SettingsModel
    private let capturesKeys: Bool

    /// `capturesKeys` is off for screenshots: the AppKit key monitor cannot be rendered.
    public init(model: SettingsModel, capturesKeys: Bool = true) {
        self.model = model
        self.capturesKeys = capturesKeys
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 20) {
                column(Array(ControlGroup.all.prefix(Self.leftColumnGroupCount)))
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(ControlGroup.all.dropFirst(Self.leftColumnGroupCount))) { groupCard($0) }
                    thresholdsCard
                }
            }
            footer
        }
        .padding(20)
        .frame(width: Self.width)
        .background {
            if capturesKeys {
                KeyCapture(isActive: model.recordingControl != nil, onKeyDown: model.handleKeyDown)
            }
        }
    }

    private static let leftColumnGroupCount = 3

    private func column(_ groups: [ControlGroup]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups) { groupCard($0) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keys").font(.title2.weight(.semibold))
            Text("Click a control, then press the key it should send to Clone Hero. Changes are saved right away.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func groupCard(_ group: ControlGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)
            Card {
                VStack(spacing: 2) {
                    ForEach(group.controls, id: \.self) { control in
                        ControlRow(
                            control: control,
                            key: model.key(for: control),
                            isRecording: model.recordingControl == control
                        ) { model.toggleRecording(control) }
                    }
                }
                .padding(.vertical, -4)
            }
        }
    }

    private var thresholdsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SENSITIVITY").font(.caption.weight(.semibold)).foregroundColor(.secondary).padding(.leading, 4)
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    thresholdRow(
                        title: "Tilt threshold",
                        explanation: "Raise the guitar past this value to trigger Tilt. It rests around 100.",
                        value: $model.tilt,
                        range: Double(SettingsModel.tiltRange.lowerBound)...Double(SettingsModel.tiltRange.upperBound),
                        step: 1,
                        formatted: { String(Int($0)) }
                    )
                    thresholdRow(
                        title: "Whammy threshold",
                        explanation: "How far to push the whammy bar before it counts as pressed.",
                        value: $model.whammy,
                        range: SettingsModel.whammyRange,
                        step: 0.05,
                        formatted: { String(format: "%.2f", $0) }
                    )
                }
            }
        }
    }

    private func thresholdRow(
        title: String,
        explanation: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formatted: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).fontWeight(.medium)
                Spacer()
                Text(formatted(value.wrappedValue)).monospacedDigit().foregroundColor(.secondary)
            }
            ValueSlider(
                value: value, range: range, step: step, accessibilityName: title, formatted: formatted,
                onCommit: model.commit
            )
            Text(explanation).font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(alignment: .top) {
            messageView
            Spacer()
            Button("Restore defaults", action: model.restoreDefaults)
                .buttonStyle(PillButtonStyle())
        }
    }

    @ViewBuilder
    private var messageView: some View {
        if let warning = model.recorderWarning {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } else if case .problem(let text) = model.message {
            Label(text, systemImage: "xmark.octagon.fill")
                .foregroundColor(.red)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.message == .saved {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.callout)
        }
    }
}

private struct ControlRow: View {
    let control: Control
    let key: KeyCode?
    let isRecording: Bool
    let action: () -> Void

    private static let chipWidth: CGFloat = 120

    var body: some View {
        Button(action: action) {
            HStack {
                Text(control.friendlyName)
                Spacer()
                Text(chipText)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(isRecording ? .white : .primary)
                    .frame(width: Self.chipWidth, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording ? Color.accentColor : Color.primary.opacity(0.1))
                    )
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(control.friendlyName)
        .accessibilityValue(isRecording ? "Recording, press a key" : (key.map(KeyLabel.text(for:)) ?? "Not bound"))
        .accessibilityHint("Click, then press the key to bind")
    }

    private var chipText: String {
        if isRecording { return "Press a key\u{2026}" }
        return key.map(KeyLabel.text(for:)) ?? "Not bound"
    }
}

/// Feeds key presses to the model while a row is recording, and swallows them so they do not beep.
private struct KeyCapture: NSViewRepresentable {
    let isActive: Bool
    let onKeyDown: (UInt16) -> Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, onKeyDown: onKeyDown)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private var monitor: Any?
        private var onKeyDown: (UInt16) -> Bool = { _ in false }

        func update(isActive: Bool, onKeyDown: @escaping (UInt16) -> Bool) {
            self.onKeyDown = onKeyDown
            if isActive, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, MainActor.assumeIsolated({ self.onKeyDown(event.keyCode) }) else { return event }
                    return nil
                }
            } else if !isActive {
                stop()
            }
        }

        func stop() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
