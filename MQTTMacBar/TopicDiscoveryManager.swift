import Foundation
import CocoaMQTT

enum DiscoveryState: Equatable {
    case idle
    case connecting
    case discovering
    case stopped
    case failed(String)

    static func == (lhs: DiscoveryState, rhs: DiscoveryState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.connecting, .connecting), (.discovering, .discovering), (.stopped, .stopped):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

final class TopicDiscoveryManager: NSObject, ObservableObject {
    struct Config {
        let broker: String
        let port: Int
        let username: String?
        let password: String?
    }

    @Published private(set) var state: DiscoveryState = .idle
    @Published private(set) var rootNodes: [TopicNode] = []
    @Published private(set) var messageCount: Int = 0
    @Published private(set) var treeVersion: Int = 0

    private var client: CocoaMQTT?
    private var nodeIndex: [String: TopicNode] = [:]

    func start(config: Config) {
        guard client == nil else { return }
        state = .connecting

        let mqtt = CocoaMQTT(
            clientID: "MQTTMacBar-discover-\(UUID().uuidString.prefix(8))",
            host: config.broker,
            port: UInt16(config.port)
        )
        mqtt.username = config.username.flatMap { $0.isEmpty ? nil : $0 }
        mqtt.password = config.password.flatMap { $0.isEmpty ? nil : $0 }
        mqtt.cleanSession = true
        mqtt.keepAlive = 30
        mqtt.delegate = self
        self.client = mqtt
        mqtt.connect()
    }

    func stop() {
        client?.delegate = nil
        client?.disconnect()
        client = nil
        if case .failed = state { } else { state = .stopped }
    }

    func reset() {
        stop()
        rootNodes = []
        nodeIndex = [:]
        messageCount = 0
        treeVersion = 0
        state = .idle
    }

    static let maxTopicDepth = 10

    // Must be called on main thread
    private func ingestMessage(topic: String, payload: String) {
        let segments = topic.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.count <= Self.maxTopicDepth else { return }
        messageCount += 1
        var currentPath = ""

        for (i, segment) in segments.enumerated() {
            currentPath = i == 0 ? segment : "\(currentPath)/\(segment)"

            if let existing = nodeIndex[currentPath] {
                if i == segments.count - 1 {
                    existing.lastMessage = payload
                    existing.messageCount += 1
                    existing.lastReceived = Date()
                    existing.jsonProperties = parseJsonProperties(payload, dotPathPrefix: "")
                }
            } else {
                let node = TopicNode(segment: segment, fullPath: currentPath)
                nodeIndex[currentPath] = node

                if i == 0 {
                    let insertIdx = rootNodes.partitioningIndex { $0.segment > segment }
                    rootNodes.insert(node, at: insertIdx)
                } else {
                    let parentPath = segments[0..<i].joined(separator: "/")
                    nodeIndex[parentPath]?.children.append(node)
                }

                if i == segments.count - 1 {
                    node.lastMessage = payload
                    node.messageCount = 1
                    node.lastReceived = Date()
                    node.jsonProperties = parseJsonProperties(payload, dotPathPrefix: "")
                }
            }
        }
        treeVersion += 1
    }

    private func parseJsonProperties(_ payload: String, dotPathPrefix: String) -> [JsonPropertyNode]? {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let nodes = buildJsonNodes(from: obj, dotPathPrefix: dotPathPrefix)
        return nodes.isEmpty ? nil : nodes
    }

    private func buildJsonNodes(from dict: [String: Any], dotPathPrefix: String) -> [JsonPropertyNode] {
        dict.sorted { $0.key < $1.key }.map { key, value in
            let dotPath = dotPathPrefix.isEmpty ? key : "\(dotPathPrefix).\(key)"
            if let nested = value as? [String: Any] {
                let node = JsonPropertyNode(key: key, dotPath: dotPath, displayValue: "{…}")
                node.children = buildJsonNodes(from: nested, dotPathPrefix: dotPath)
                return node
            } else {
                return JsonPropertyNode(key: key, dotPath: dotPath, displayValue: "\(value)")
            }
        }
    }
}

extension TopicDiscoveryManager: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        DispatchQueue.main.async {
            guard ack == .accept else {
                self.state = .failed("Broker rejected connection (code \(ack.rawValue))")
                return
            }
            self.state = .discovering
            mqtt.subscribe("#", qos: .qos0)
            mqtt.subscribe("$SYS/#", qos: .qos0)
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let topic = message.topic
        let payload = message.string ?? ""
        DispatchQueue.main.async { self.ingestMessage(topic: topic, payload: payload) }
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        DispatchQueue.main.async {
            if let err = err, case .discovering = self.state {
                self.state = .failed(err.localizedDescription)
            }
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        if failed.contains("#") {
            DispatchQueue.main.async {
                self.state = .failed("Broker denied wildcard '#' subscription")
            }
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
}

extension Collection {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
        var lo = startIndex
        var hi = endIndex
        while lo < hi {
            let mid = index(lo, offsetBy: distance(from: lo, to: hi) / 2)
            if predicate(self[mid]) {
                hi = mid
            } else {
                lo = index(after: mid)
            }
        }
        return lo
    }
}
