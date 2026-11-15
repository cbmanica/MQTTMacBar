import Foundation
import OSLog
import CocoaMQTT

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "mqtt")

struct MqttMessageContext {
    let topic: String
    let rawMessage: String
    let displayValue: String
    let previousRawMessage: String?
}

protocol MQTTClientDelegate: AnyObject {
    func clientDidReceiveMessage(context: MqttMessageContext, subscriptionID: UUID)
    func clientDidConnect()
    func clientDidDisconnect()
}

class MqttManager {
    weak var delegate: MQTTClientDelegate?
    var mqttClient: CocoaMQTT!
    private var subscriptions: [TopicSubscription]
    private var subscriptionByTopic: [String: TopicSubscription]
    private var previousMessages: [UUID: String] = [:]
    private let reconnectDelay: TimeInterval = 3.0

    // UserDefaults keys (non-sensitive)
    static let mqttBrokerKey = "mqttBroker"
    static let mqttPortKey = "mqttPort"
    static let mqttUseSSLKey = "mqttUseSSL"
    // Legacy single-topic keys kept for migration reads
    static let mqttTopicKey = "mqttTopic"
    static let mqttJsonKeyPathKey = "mqttJsonKeyPath"
    static let mqttDisplayLabelKey = "mqttDisplayLabel"

    // Keychain account names (sensitive)
    static let mqttUsernameKey = "mqttUsername"
    static let mqttPasswordKey = "mqttPassword"

    static func areMqttSettingsComplete() -> Bool {
        let defaults = UserDefaults.standard
        guard let broker = defaults.string(forKey: mqttBrokerKey), !broker.isEmpty,
              defaults.integer(forKey: mqttPortKey) > 0 else { return false }
        if let subs = TopicSubscription.loadAll(), !subs.isEmpty { return true }
        return defaults.string(forKey: mqttTopicKey) != nil
    }

    init(delegate: MQTTClientDelegate, subscriptions: [TopicSubscription]) {
        self.delegate = delegate
        self.subscriptions = subscriptions
        self.subscriptionByTopic = Dictionary(
            uniqueKeysWithValues: subscriptions.map { ($0.topic, $0) }
        )

        let defaults = UserDefaults.standard

        guard let broker = defaults.string(forKey: MqttManager.mqttBrokerKey),
              let port = defaults.object(forKey: MqttManager.mqttPortKey) as? Int else {
            log.error("Failed to load MQTT configuration. Cannot initialize MqttManager.")
            delegate.clientDidDisconnect()
            return
        }

        let username = KeychainManager.load(account: MqttManager.mqttUsernameKey)
        let password = KeychainManager.load(account: MqttManager.mqttPasswordKey)

        let topics = subscriptions.map(\.topic)
        let passwordStatus = password != nil ? "set" : "not set"
        log.info("MQTT settings loaded — broker: \(broker, privacy: .public):\(port, privacy: .public), topics: \(topics, privacy: .public), username: \(username ?? "N/A", privacy: .public), password: \(passwordStatus, privacy: .public)")

        let clientID = "MQTTMacBar-\(UUID().uuidString.prefix(8))"
        self.mqttClient = CocoaMQTT(clientID: clientID, host: broker, port: UInt16(port))
        self.mqttClient.username = username
        self.mqttClient.password = password
        self.mqttClient.enableSSL = defaults.bool(forKey: MqttManager.mqttUseSSLKey)
        self.mqttClient.cleanSession = true
        self.mqttClient.keepAlive = 60
        self.mqttClient.delegate = self
        let _ = self.mqttClient.connect()
    }

    private func matchSubscription(for incomingTopic: String) -> TopicSubscription? {
        if let exact = subscriptionByTopic[incomingTopic] { return exact }
        return subscriptions.first { Self.matchesTopic($0, incomingTopic: incomingTopic) }
    }

    // Internal static so it can be unit-tested without an MqttManager instance.
    static func matchesTopic(_ sub: TopicSubscription, incomingTopic: String) -> Bool {
        if sub.topic == incomingTopic { return true }
        if sub.topic == "#" { return true }
        guard sub.topic.hasSuffix("/#") else { return false }
        let prefix = String(sub.topic.dropLast(2))
        return incomingTopic.hasPrefix(prefix + "/") || incomingTopic == prefix
    }

    private func extractDisplayValue(raw: String, keyPath: String?) -> String {
        guard let keyPath = keyPath, !keyPath.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extracted = Self.extractValue(from: json, keyPath: keyPath) else {
            return raw
        }
        return extracted
    }

    // Internal static so it can be unit-tested without an MqttManager instance.
    static func extractValue(from json: [String: Any], keyPath: String) -> String? {
        let keys = keyPath.split(separator: ".").map(String.init)
        var current: Any = json
        for key in keys {
            guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
            current = next
        }
        return "\(current)"
    }
}

extension MqttManager: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if ack == .accept {
            let count = subscriptions.count
            log.info("MQTT connected, subscribing to \(count, privacy: .public) topic(s)")
            delegate?.clientDidConnect()
            for sub in subscriptions {
                mqtt.subscribe(sub.topic)
            }
        } else {
            log.error("MQTT connection refused, ack: \(ack.rawValue, privacy: .public)")
            delegate?.clientDidDisconnect()
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        guard let rawString = message.string else { return }
        let incomingTopic = message.topic
        log.debug("MQTT received on \(incomingTopic, privacy: .public): \(rawString, privacy: .public)")

        guard let sub = matchSubscription(for: incomingTopic) else {
            log.info("No matching subscription for topic: \(incomingTopic, privacy: .public)")
            return
        }

        let displayValue = extractDisplayValue(raw: rawString, keyPath: sub.jsonKeyPath)
        let prev = previousMessages[sub.id]
        let context = MqttMessageContext(
            topic: incomingTopic,
            rawMessage: rawString,
            displayValue: displayValue,
            previousRawMessage: prev
        )
        previousMessages[sub.id] = rawString
        delegate?.clientDidReceiveMessage(context: context, subscriptionID: sub.id)
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        log.info("MQTT disconnected — error: \(err?.localizedDescription ?? "none", privacy: .public)")
        delegate?.clientDidDisconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            guard let self = self else { return }
            log.info("Attempting to reconnect MQTT")
            let _ = self.mqttClient.connect()
        }
    }
}

extension MqttManager {
    func reconnect() {
        if let mqttClient = self.mqttClient {
            log.info("Reconnecting MQTT client")
            let _ = mqttClient.connect()
        } else {
            log.error("MQTT client not initialized, cannot reconnect")
        }
    }
}
