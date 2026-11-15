import Foundation

final class TopicNode: ObservableObject, Identifiable {
    let id: String
    let segment: String
    let fullPath: String

    @Published var children: [TopicNode] = []
    @Published var lastMessage: String = ""
    @Published var messageCount: Int = 0
    @Published var lastReceived: Date? = nil
    @Published var jsonProperties: [JsonPropertyNode]? = nil

    var childrenOrNil: [TopicNode]? { children.isEmpty ? nil : children }

    var childrenByTimeOrNil: [TopicNode]? {
        guard !children.isEmpty else { return nil }
        return children.sorted {
            ($0.latestDescendantUpdate ?? .distantPast) > ($1.latestDescendantUpdate ?? .distantPast)
        }
    }

    var descendantLeafCount: Int {
        if children.isEmpty { return 1 }
        return children.reduce(0) { $0 + $1.descendantLeafCount }
    }

    var latestDescendantUpdate: Date? {
        if children.isEmpty { return lastReceived }
        return children.compactMap { $0.latestDescendantUpdate }.max()
    }

    init(segment: String, fullPath: String) {
        self.segment = segment
        self.fullPath = fullPath
        self.id = fullPath.isEmpty ? "__root__" : fullPath
    }
}

final class JsonPropertyNode: ObservableObject, Identifiable {
    let id: String
    let key: String
    let dotPath: String
    let displayValue: String

    @Published var children: [JsonPropertyNode]? = nil

    var childrenOrNil: [JsonPropertyNode]? { children.flatMap { $0.isEmpty ? nil : $0 } }

    init(key: String, dotPath: String, displayValue: String) {
        self.key = key
        self.dotPath = dotPath
        self.displayValue = displayValue
        self.id = dotPath
    }
}
