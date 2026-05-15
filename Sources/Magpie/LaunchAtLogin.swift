import Foundation
import ServiceManagement

/// Thin wrapper around SMAppService.mainApp so the popover doesn't import
/// ServiceManagement directly and we get a clearer error story.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, an error message on failure.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return nil
        } catch {
            NSLog("Magpie: launch-at-login toggle failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:           return "Enabled"
        case .notRegistered:     return "Not registered"
        case .notFound:          return "App not found"
        case .requiresApproval:  return "Awaiting approval in System Settings"
        @unknown default:        return "Unknown"
        }
    }
}
