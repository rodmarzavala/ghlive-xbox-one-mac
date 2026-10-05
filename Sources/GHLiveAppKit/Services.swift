import Foundation
import KeyboardOutput
import ServiceManagement

/// Seam over `AccessibilityPermission` so the first-run flow is testable.
@MainActor
public protocol AccessibilityChecking {
    var isTrusted: Bool { get }
    func request()
}

@MainActor
public struct SystemAccessibility: AccessibilityChecking {
    public init() {}

    public var isTrusted: Bool { AccessibilityPermission.isTrusted }

    public func request() {
        AccessibilityPermission.request()
    }
}

/// Dry-run sessions post no key events, so they never need the permission.
@MainActor
public struct NoAccessibilityNeeded: AccessibilityChecking {
    public init() {}

    public var isTrusted: Bool { true }

    public func request() {}
}

public enum LaunchAtLoginState: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but the user still has to switch it on in System Settings > Login Items.
    case requiresApproval
}

/// Seam over `SMAppService.mainApp`.
@MainActor
public protocol LaunchAtLoginControlling {
    var state: LaunchAtLoginState { get }
    func setEnabled(_ enabled: Bool) throws
    func openLoginItemsSettings()
}

@MainActor
public struct SystemLaunchAtLogin: LaunchAtLoginControlling {
    public init() {}

    public var state: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

public enum SystemLinks {
    public static let accessibilitySettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
}
