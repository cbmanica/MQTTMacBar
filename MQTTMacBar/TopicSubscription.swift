import Foundation

struct TopicSubscription: Codable, Identifiable, Equatable {
    var id: UUID
    var topic: String
    var jsonKeyPath: String?
    var label: String?
    var showInMenuBar: Bool

    init(id: UUID = UUID(), topic: String, jsonKeyPath: String? = nil, label: String? = nil, showInMenuBar: Bool = true) {
        self.id = id
        self.topic = topic
        self.jsonKeyPath = jsonKeyPath.flatMap { $0.isEmpty ? nil : $0 }
        self.label = label.flatMap { $0.isEmpty ? nil : $0 }
        self.showInMenuBar = showInMenuBar
    }

    // Custom decoder so existing saved data (without showInMenuBar) defaults to true
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        topic = try c.decode(String.self, forKey: .topic)
        jsonKeyPath = try c.decodeIfPresent(String.self, forKey: .jsonKeyPath)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
    }

    static let userDefaultsKey = "mqttTopicSubscriptions"

    static func loadAll() -> [TopicSubscription]? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode([TopicSubscription].self, from: data)
    }

    static func saveAll(_ subscriptions: [TopicSubscription]) {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    static func migrateFromLegacy() -> [TopicSubscription]? {
        let defaults = UserDefaults.standard
        guard let topic = defaults.string(forKey: MqttManager.mqttTopicKey), !topic.isEmpty else { return nil }
        let keyPath = defaults.string(forKey: MqttManager.mqttJsonKeyPathKey)
        let label = defaults.string(forKey: MqttManager.mqttDisplayLabelKey)
        return [TopicSubscription(topic: topic, jsonKeyPath: keyPath, label: label)]
    }
}
