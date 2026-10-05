import AppKit
import GuitarInput
import KeyMapping
import SwiftUI

public struct SettingsView: View {
    public static let width: CGFloat = 780

    @ObservedObject private var model: SettingsModel
    private let capturesKeys: Bool

    private static let leftColumnGroupCount = 3
    private static let sliderStep = 1.0
    private static let whammyStep = 0.05

    /// `capturesKeys` is off for screenshots: the AppKit key monitor cannot be rendered.
    public init(model: SettingsModel, capturesKeys: Bool = true) {
        self.model = model
        self.capturesKeys = capturesKeys
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            GlassGroup {
                VStack(alignment: .leading, spacing: 14) {
                    if case .unreadableKeymap(let detail) = model.message { unreadableKeymapCard(detail) }
                    HStack(alignment: .top, spacing: 20) {
                        column(Array(ControlGroup.all.prefix(Self.leftColumnGroupCount)))
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(ControlGroup.all.dropFirst(Self.leftColumnGroupCount))) { groupCard($0) }
                            thresholdsCard
                        }
                    }
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
        .onDisappear { model.cancelRecording() }
        .alert(
            "Restore default keys and sensitivity?",
            isPresented: Binding(
                get: { model.isConfirmingRestore },
                set: { if !$0 { model.cancelRestoreDefaults() } })
        ) {
            Button("Restore", role: .destructive, action: model.confirmRestoreDefaults)
            Button("Cancel", role: .cancel, action: model.cancelRestoreDefaults)
        } message: {
            Text("Your current setup will be replaced.")
        }
    }

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

    private func unreadableKeymapCard(_ detail: String) -> some View {
        Card(emphasis: .red) {
            VStack(alignment: .leading, spacing: 6) {
                NoticeLabel(
                    text: SettingsCopy.unreadableKeymapHeadline, symbol: "xmark.octagon.fill", color: .red
                )
                .font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Fix the file, or choose Restore defaults to replace it with a working setup.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open keymap folder", action: model.onOpenKeymapFolder)
                    .ghButtonStyle(prominent: false)
            }
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
                        step: Self.sliderStep,
                        formatted: { String(Int($0)) }
                    )
                    thresholdRow(
                        title: "Whammy threshold",
                        explanation:
                            "How far to push the whammy bar before it counts as pressed. 0 = released, 1 = fully pushed.",
                        value: $model.whammy,
                        range: SettingsModel.whammyRange,
                        step: Self.whammyStep,
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
        HStack(alignment: .top, spacing: 16) {
            messageView.frame(maxWidth: .infinity, alignment: .leading)
            Button("Restore defaults", action: model.requestRestoreDefaults)
                .ghButtonStyle(prominent: false)
        }
    }

    @ViewBuilder
    private var messageView: some View {
        if let warning = model.recorderWarning {
            NoticeLabel(text: warning, symbol: "exclamationmark.triangle.fill", color: .orange)
                .font(.callout)
                .lineLimit(2)
        } else if model.recordingControl != nil {
            Text("Press a key, or click the control again to cancel").font(.callout).foregroundColor(.secondary)
        } else if case .problem(let text) = model.message {
            NoticeLabel(text: text, symbol: "xmark.octagon.fill", color: .red).font(.callout)
        } else if model.message == .saved {
            VStack(alignment: .leading, spacing: 2) {
                NoticeLabel(text: "Saved", symbol: "checkmark.circle.fill", color: .green)
                    .font(.callout).foregroundColor(.secondary)
                if let note = model.hysteresisNote {
                    Text(note).font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ControlRow: View {
    let control: Control
    let key: KeyCode?
    let isRecording: Bool
    let action: () -> Void

    private static let chipWidth: CGFloat = 120
    private static let chipHeight: CGFloat = 26

    var body: some View {
        Button(action: action) {
            HStack {
                Text(control.friendlyName)
                Spacer()
                Text(chipText)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(isRecording ? .white : .primary)
                    .frame(width: Self.chipWidth, height: Self.chipHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording ? Color.accentColor : Color.primary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.3), lineWidth: 1)
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
    let onKeyDown: (UInt16, NSEvent.ModifierFlags) -> Bool

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
        private var onKeyDown: (UInt16, NSEvent.ModifierFlags) -> Bool = { _, _ in false }

        func update(isActive: Bool, onKeyDown: @escaping (UInt16, NSEvent.ModifierFlags) -> Bool) {
            self.onKeyDown = onKeyDown
            if isActive, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    // NSEvent is not Sendable and Swift 6.0 rejects capturing it in `assumeIsolated`, so read it first.
                    let keyCode = event.keyCode
                    let modifiers = event.modifierFlags
                    guard let self, MainActor.assumeIsolated({ self.onKeyDown(keyCode, modifiers) }) else {
                        return event
                    }
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
