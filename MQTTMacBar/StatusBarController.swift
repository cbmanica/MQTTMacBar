import AppKit
import SwiftUI
import CocoaMQTT

private let mqttPurple = NSColor(red: 0.55, green: 0.0, blue: 0.75, alpha: 1.0)

// MARK: - StatusBarContentView

// Custom view added as a subview of NSStatusBarButton so layout() is called
// with the correct bounds whenever AppKit re-lays out for a new monitor.
// This is more reliable than KVO on button.frame, which may not fire when
// the active menu bar moves between monitors without changing the frame value.
private class StatusBarContentView: NSView {
    private weak var button: NSStatusBarButton?
    private var highlightObs: NSKeyValueObservation?

    var displayValue: String = "" { didSet { setNeedsDisplay(bounds) } }
    var displayLabel: String? { didSet { setNeedsDisplay(bounds) } }
    var hasUnseen: Bool = false { didSet { setNeedsDisplay(bounds) } }

    init(button: NSStatusBarButton) {
        self.button = button
        super.init(frame: button.bounds)
        autoresizingMask = [.width, .height]
        button.addSubview(self)
        highlightObs = button.observe(\.isHighlighted) { [weak self] _, _ in
            self?.setNeedsDisplay(self?.bounds ?? .zero)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // Transparent to hit testing so click events reach the button underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = button?.isHighlighted ?? false
        let attrStr = makeAttrStr(value: displayValue, label: displayLabel, highlighted: highlighted)
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let blockSize = attrStr.boundingRect(with: NSSize(width: bounds.width, height: 1000), options: opts)
        let blockHeight = blockSize.height > 0 ? ceil(blockSize.height) : 22
        let yOffset = max(0, floor((bounds.height - blockHeight) / 2))
        attrStr.draw(with: NSRect(x: 0, y: yOffset, width: bounds.width, height: blockHeight + 2), options: opts)
    }

    func setContent(value: String, label: String?) {
        displayValue = value
        displayLabel = label
        // Keep button.attributedTitle in sync with clear-colored text so that
        // NSStatusItem(variableLength) can measure the correct button width.
        // Our draw() renders the visible version on top.
        if let button = button {
            let sized = NSMutableAttributedString(attributedString: makeAttrStr(value: value, label: label, highlighted: false))
            sized.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(location: 0, length: sized.length))
            button.attributedTitle = sized
        }
    }

    private func makeAttrStr(value: String, label: String?, highlighted: Bool) -> NSAttributedString {
        let textColor: NSColor = highlighted ? .white : .labelColor
        let secondaryColor: NSColor = highlighted ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
        let dotColor: NSColor = highlighted ? .white : (hasUnseen ? .systemRed : mqttPurple)

        let colorDotFont = NSFont.systemFont(ofSize: 14.0)
        switch value.lowercased() {
        case "red":
            let c = highlighted ? NSColor.white : NSColor.systemRed
            return NSAttributedString(string: "●", attributes: [.foregroundColor: c, .font: colorDotFont, .baselineOffset: -1.0])
        case "yellow":
            let c = highlighted ? NSColor.white : NSColor.systemYellow
            return NSAttributedString(string: "●", attributes: [.foregroundColor: c, .font: colorDotFont, .baselineOffset: -1.0])
        case "green":
            let c = highlighted ? NSColor.white : NSColor.systemGreen
            return NSAttributedString(string: "●", attributes: [.foregroundColor: c, .font: colorDotFont, .baselineOffset: -1.0])
        case "no_color":
            return NSAttributedString(string: " ")
        default:
            break
        }

        guard let label = label, !label.isEmpty else {
            let para = NSMutableParagraphStyle()
            para.alignment = .left
            let result = NSMutableAttributedString()
            result.append(NSAttributedString(string: "● ", attributes: [
                .font: NSFont.systemFont(ofSize: 9.0),
                .foregroundColor: dotColor,
                .baselineOffset: 0.5,
                .paragraphStyle: para
            ]))
            result.append(NSAttributedString(string: value, attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
                .foregroundColor: textColor,
                .baselineOffset: -1.0,
                .paragraphStyle: para
            ]))
            return result
        }

        // Stacked layout: "● LABEL" above "VALUE", centered.
        // Vertical positioning is handled by the draw() centering logic,
        // so no barHeight-dependent baselineOffset is needed here.
        let labelPara = NSMutableParagraphStyle()
        labelPara.alignment = .center
        labelPara.minimumLineHeight = 9.0
        labelPara.maximumLineHeight = 9.0

        let valuePara = NSMutableParagraphStyle()
        valuePara.alignment = .center
        valuePara.minimumLineHeight = 11.0
        valuePara.maximumLineHeight = 11.0
        valuePara.paragraphSpacingBefore = 2.0

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "● ", attributes: [
            .font: NSFont.systemFont(ofSize: 7.0),
            .foregroundColor: dotColor,
            .paragraphStyle: labelPara,
            .baselineOffset: 0
        ]))
        result.append(NSAttributedString(string: label.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 7.5, weight: .regular),
            .foregroundColor: secondaryColor,
            .paragraphStyle: labelPara,
            .baselineOffset: 0
        ]))
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 7.5),
            .paragraphStyle: labelPara,
            .baselineOffset: 0
        ]))
        result.append(NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: 12.0, weight: .bold),
            .foregroundColor: textColor,
            .paragraphStyle: valuePara,
            .baselineOffset: 0
        ]))
        return result
    }
}

// MARK: - StatusBarController

class StatusBarController: NSObject {
    private var statusItems: [UUID: NSStatusItem] = [:]
    private var contentViews: [UUID: StatusBarContentView] = [:]
    private var menuSubscriptionIDs: [NSMenu: UUID] = [:]
    private var mqttManager: MqttManager?
    private var subscriptions: [TopicSubscription] = []

    // Shown when no subscriptions have showInMenuBar == true
    private var fallbackStatusItem: NSStatusItem?

    // Settings windows (retained while open)
    private var connectionSettingsWindow: NSWindow?
    private var topicSubscriptionsWindow: NSWindow?

    let stats = SubscriptionStats()
    let connectionState = ConnectionState()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f
    }()

    override init() {
        super.init()
        setupMqtt()
    }

    private func setupMqtt() {
        subscriptions = TopicSubscription.loadAll() ?? []
        let visible = subscriptions.filter(\.showInMenuBar)

        if visible.isEmpty {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            fallbackStatusItem = item
            item.button?.title = "MQTT"
            createMenu(for: item, subscriptionID: nil)
        } else {
            for sub in visible.reversed() {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                statusItems[sub.id] = item
                if let button = item.button {
                    contentViews[sub.id] = StatusBarContentView(button: button)
                }
                setItemText("MQTT", subscriptionID: sub.id)
                createMenu(for: item, subscriptionID: sub.id)
            }
        }

        mqttManager = MqttManager(delegate: self, subscriptions: subscriptions)
    }

    private func createMenu(for item: NSStatusItem, subscriptionID: UUID?) {
        let menu = NSMenu()
        if let id = subscriptionID {
            menuSubscriptionIDs[menu] = id
        }
        menu.delegate = self

        // rebuildInfoItems inserts data items before this leading separator
        menu.addItem(NSMenuItem.separator())

        let connItem = NSMenuItem(title: "Connection Settings…", action: #selector(openConnectionSettings), keyEquivalent: "")
        connItem.target = self
        let subsItem = NSMenuItem(title: "Topic Subscriptions…", action: #selector(openTopicSubscriptions), keyEquivalent: "")
        subsItem.target = self

        menu.addItem(connItem)
        menu.addItem(subsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func pauseMqtt() {
        mqttManager = nil
        for (_, item) in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        if let fallback = fallbackStatusItem {
            NSStatusBar.system.removeStatusItem(fallback)
            fallbackStatusItem = nil
        }
        statusItems = [:]
        contentViews = [:]
        menuSubscriptionIDs = [:]
        subscriptions = []
    }

    func restartMqtt() {
        pauseMqtt()
        setupMqtt()
    }

    // MARK: - Status bar text rendering

    private func setItemText(_ text: String, subscriptionID: UUID) {
        let sub = subscriptions.first(where: { $0.id == subscriptionID })
        let cv = contentViews[subscriptionID]
        DispatchQueue.main.async {
            cv?.setContent(value: text, label: sub?.label)
        }
    }

    // MARK: - Menu info items

    private func rebuildInfoItems(in menu: NSMenu, subscriptionID: UUID) {
        while menu.numberOfItems > 0 {
            let item = menu.item(at: 0)!
            if item.isSeparatorItem { break }
            menu.removeItem(at: 0)
        }

        var insertIndex = 0

        guard let ctx = stats.lastContext[subscriptionID] else {
            menu.insertItem(infoItem("No messages yet"), at: insertIndex)
            return
        }

        let count = stats.messageCount[subscriptionID] ?? 0
        if let t = stats.lastReceived[subscriptionID] {
            menu.insertItem(statsInfoItem(count: count, time: t), at: insertIndex)
            insertIndex += 1
        }

        menu.insertItem(infoItem("Topic: \(ctx.topic)"), at: insertIndex)
        insertIndex += 1

        let sub = subscriptions.first(where: { $0.id == subscriptionID })
        let keyPath = sub?.jsonKeyPath ?? ""
        if !keyPath.isEmpty,
           let data = ctx.rawMessage.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in json.keys.sorted() {
                let val = json[key].map { anyToString($0) } ?? "nil"
                let raw = "  \(key): \(val)"
                let truncated = raw.count > 80 ? String(raw.prefix(77)) + "…" : raw
                menu.insertItem(infoItem(truncated), at: insertIndex)
                insertIndex += 1
            }
        }

        let diffs = buildDiffLines(old: ctx.previousRawMessage, new: ctx.rawMessage)
        if !diffs.isEmpty {
            menu.insertItem(infoItem("Changes:"), at: insertIndex)
            insertIndex += 1
            for line in diffs {
                menu.insertItem(infoItem("  " + line.text), at: insertIndex)
                insertIndex += 1
            }
        }
    }

    private func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func statsInfoItem(count: Int, time: Date) -> NSMenuItem {
        let countStr = "\(count) msg\(count == 1 ? "" : "s")"
        let timeStr = Self.timeFmt.string(from: time)
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: countStr, attributes: [.foregroundColor: NSColor.systemOrange]))
        attr.append(NSAttributedString(string: "   "))
        attr.append(NSAttributedString(string: timeStr, attributes: [.foregroundColor: NSColor.systemBlue]))
        let item = NSMenuItem()
        item.attributedTitle = attr
        item.isEnabled = false
        return item
    }

    // MARK: - Window management

    @objc private func openConnectionSettings() {
        if let existing = connectionSettingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Connection Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let view = ConnectionSettingsView(
            connectionState: connectionState,
            onSave: { [weak self, weak window] in
                window?.close()
                self?.connectionSettingsWindow = nil
                self?.restartMqtt()
            },
            onCancel: { [weak self, weak window] in
                window?.close()
                self?.connectionSettingsWindow = nil
            }
        )
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        connectionSettingsWindow = window
    }

    @objc private func openTopicSubscriptions() {
        if let existing = topicSubscriptionsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Topic Subscriptions"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let view = TopicSubscriptionsView(
            stats: stats,
            connectionState: connectionState,
            onMarkAllSeen: { [weak self] in
                guard let self = self else { return }
                for (_, cv) in self.contentViews {
                    cv.hasUnseen = false
                }
            },
            onSave: { [weak self, weak window] in
                window?.close()
                self?.topicSubscriptionsWindow = nil
                self?.restartMqtt()
            },
            onCancel: { [weak self, weak window] in
                window?.close()
                self?.topicSubscriptionsWindow = nil
            }
        )
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        topicSubscriptionsWindow = window
    }
}

// MARK: - NSWindowDelegate

extension StatusBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === connectionSettingsWindow {
            connectionSettingsWindow = nil
        } else if w === topicSubscriptionsWindow {
            topicSubscriptionsWindow = nil
        }
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard let id = menuSubscriptionIDs[menu] else { return }
        rebuildInfoItems(in: menu, subscriptionID: id)
        stats.markSeen(id)
        contentViews[id]?.hasUnseen = false
    }
}

// MARK: - MQTTClientDelegate

extension StatusBarController: MQTTClientDelegate {
    func clientDidConnect() {
        DispatchQueue.main.async {
            self.connectionState.markConnected()
            for sub in self.subscriptions {
                self.setItemText("–", subscriptionID: sub.id)
            }
            self.fallbackStatusItem?.button?.title = "–"
        }
    }

    func clientDidDisconnect() {
        DispatchQueue.main.async {
            self.connectionState.markDisconnected()
            for sub in self.subscriptions {
                self.setItemText("MQTT", subscriptionID: sub.id)
            }
            self.fallbackStatusItem?.button?.title = "MQTT"
        }
    }

    func clientDidReceiveMessage(context: MqttMessageContext, subscriptionID: UUID) {
        DispatchQueue.main.async {
            self.stats.recordMessage(context, id: subscriptionID)
            self.contentViews[subscriptionID]?.hasUnseen = true
            self.setItemText(context.displayValue, subscriptionID: subscriptionID)
        }
    }
}
