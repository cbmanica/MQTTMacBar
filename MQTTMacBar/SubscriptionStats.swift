import Foundation

final class SubscriptionStats: ObservableObject {
    @Published var messageCount: [UUID: Int] = [:]
    @Published var lastReceived: [UUID: Date] = [:]
    @Published var lastContext: [UUID: MqttMessageContext] = [:]
    @Published var hasUnseen: [UUID: Bool] = [:]

    // Called on main thread only
    func recordMessage(_ ctx: MqttMessageContext, id: UUID) {
        messageCount[id, default: 0] += 1
        lastReceived[id] = Date()
        lastContext[id] = ctx
        hasUnseen[id] = true
    }

    func markSeen(_ id: UUID) {
        hasUnseen[id] = false
    }

    func markAllSeen() {
        for key in hasUnseen.keys {
            hasUnseen[key] = false
        }
    }
}
