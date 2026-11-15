import Foundation

final class ConnectionState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectedAt: Date? = nil

    func markConnected() {
        isConnected = true
        connectedAt = Date()
    }

    func markDisconnected() {
        isConnected = false
        connectedAt = nil
    }
}
