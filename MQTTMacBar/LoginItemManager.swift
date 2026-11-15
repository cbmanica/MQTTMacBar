
import Foundation
import OSLog
import ServiceManagement

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "loginItem")

class LoginItemManager {
    static func setLaunchAtLogin(enabled: Bool) {
        if enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                log.error("Failed to register login item: \(error, privacy: .public)")
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                log.error("Failed to unregister login item: \(error, privacy: .public)")
            }
        }
    }

    static func launchAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    static var isInstalledBuild: Bool {
        let installPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications/MQTTMacBar.app").path
        return Bundle.main.bundlePath == installPath
    }
}
