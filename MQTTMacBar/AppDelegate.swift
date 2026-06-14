
import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusBarController: StatusBarController?
    var setupWindow: NSWindow?
    private var closingFromSave = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        terminateOtherInstances()
        migrateSettingsIfNeeded()

        if !MqttManager.areMqttSettingsComplete() {
            showSetupWindow()
        } else {
            setupStatusBarApp()
        }
    }

    private func migrateSettingsIfNeeded() {
        guard TopicSubscription.loadAll() == nil,
              let migrated = TopicSubscription.migrateFromLegacy() else { return }
        TopicSubscription.saveAll(migrated)
    }

    private func terminateOtherInstances() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }
        for app in others {
            app.terminate()
        }
        if !others.isEmpty {
            // Give the other instance a moment to exit cleanly
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    func setupStatusBarApp() {
        if statusBarController == nil {
            statusBarController = StatusBarController()
        }
    }

    func showSetupWindow() {
        setupWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        setupWindow?.center()
        setupWindow?.setFrameAutosaveName("MQTTSetupWindow")
        setupWindow?.isReleasedWhenClosed = false
        setupWindow?.delegate = self

        let setupView = SetupView { [weak self] in
            self?.closingFromSave = true
            self?.setupWindow?.close()
            self?.closingFromSave = false
            if self?.statusBarController == nil {
                self?.setupStatusBarApp()
            } else {
                self?.statusBarController?.restartMqtt()
            }
        }
        setupWindow?.contentView = NSHostingView(rootView: setupView)
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === setupWindow else { return }
        guard !closingFromSave else { return }
        // Only reconnect if we already have a controller (reset-settings path).
        // First-time setup close via X: controller is nil, do nothing.
        statusBarController?.restartMqtt()
    }
}
