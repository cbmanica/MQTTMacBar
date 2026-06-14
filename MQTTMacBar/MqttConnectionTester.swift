import Foundation
import CocoaMQTT

class MqttConnectionTester: NSObject {
    private var client: CocoaMQTT?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var timeoutWork: DispatchWorkItem?
    private var settled = false

    struct ConnectionError: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    func test(broker: String, port: Int, username: String?, password: String?,
              useSSL: Bool = false, timeout: TimeInterval = 5.0,
              completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion

        let mqtt = CocoaMQTT(clientID: "MQTTMacBar-test-\(UUID().uuidString.prefix(8))",
                             host: broker, port: UInt16(port))
        mqtt.username = username.flatMap { $0.isEmpty ? nil : $0 }
        mqtt.password = password.flatMap { $0.isEmpty ? nil : $0 }
        mqtt.enableSSL = useSSL
        mqtt.cleanSession = true
        mqtt.keepAlive = 10
        mqtt.delegate = self
        self.client = mqtt

        let work = DispatchWorkItem { [weak self] in
            self?.finish(.failure(ConnectionError(reason: "Connection timed out")))
        }
        self.timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)

        mqtt.connect()
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !settled else { return }
        settled = true
        timeoutWork?.cancel()
        client?.delegate = nil
        client?.disconnect()
        client = nil
        DispatchQueue.main.async { [weak self] in
            self?.completion?(result)
            self?.completion = nil
        }
    }
}

extension MqttConnectionTester: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if ack == .accept {
            finish(.success(()))
        } else {
            finish(.failure(ConnectionError(reason: "Broker rejected connection (code \(ack.rawValue))")))
        }
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        if let err {
            finish(.failure(err))
        } else {
            finish(.failure(ConnectionError(reason: "Disconnected before handshake completed")))
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
}
