import Foundation

/// The windows besides the menu; the raw value is the scene id.
public enum AppWindow: String, CaseIterable, Sendable {
    case settings
    case monitor
    case charts
}

public enum LaunchOptions: Equatable, Sendable {
    case runApp
    case exportScreenshots(directory: URL)
    case invalid(String)

    public static let exportScreenshotsFlag = "--export-screenshots"

    /// `arguments` excludes the program name.
    public static func parse(_ arguments: [String]) -> LaunchOptions {
        guard let flagIndex = arguments.firstIndex(of: exportScreenshotsFlag) else { return .runApp }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else {
            return .invalid("\(exportScreenshotsFlag) needs a directory")
        }
        return .exportScreenshots(directory: URL(fileURLWithPath: arguments[valueIndex], isDirectory: true))
    }

    public static let openWindowFlag = "--open-window"

    /// The window to open at launch, for visual checks. Honoured only in dry-run mode, so a stray flag can
    /// never change what a normal launch does. `arguments` excludes the program name.
    @MainActor public static func initialWindow(arguments: [String], environment: [String: String]) -> AppWindow? {
        guard AppModel.isDryRun(environment: environment),
            let flagIndex = arguments.firstIndex(of: openWindowFlag),
            arguments.indices.contains(flagIndex + 1)
        else { return nil }
        return AppWindow(rawValue: arguments[flagIndex + 1])
    }
}
