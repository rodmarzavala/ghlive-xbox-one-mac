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

/// Seam over `SMAppService.mainApp`.
@MainActor
public protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
public struct SystemLaunchAtLogin: LaunchAtLoginControlling {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

public enum SystemLinks {
    public static let accessibilitySettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
}
