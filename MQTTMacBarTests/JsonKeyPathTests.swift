import XCTest
@testable import MQTTMacBar

final class JsonKeyPathTests: XCTestCase {

    func testTopLevelKey() {
        let json: [String: Any] = ["temperature": 72]
        XCTAssertEqual(MqttManager.extractValue(from: json, keyPath: "temperature"), "72")
    }

    func testNestedPath() {
        let json: [String: Any] = ["sensors": ["temperature": 72.5]]
        XCTAssertEqual(MqttManager.extractValue(from: json, keyPath: "sensors.temperature"), "72.5")
    }

    func testMissingTopLevelKey_returnsNil() {
        let json: [String: Any] = ["a": 1]
        XCTAssertNil(MqttManager.extractValue(from: json, keyPath: "missing"))
    }

    func testMissingNestedKey_returnsNil() {
        let json: [String: Any] = ["sensors": ["humidity": 50]]
        XCTAssertNil(MqttManager.extractValue(from: json, keyPath: "sensors.temperature"))
    }

    func testStringValue() {
        let json: [String: Any] = ["status": "ok"]
        XCTAssertEqual(MqttManager.extractValue(from: json, keyPath: "status"), "ok")
    }

    func testBoolValue() {
        let json: [String: Any] = ["active": true]
        XCTAssertEqual(MqttManager.extractValue(from: json, keyPath: "active"), "true")
    }

    func testThreeLevelPath() {
        let json: [String: Any] = ["a": ["b": ["c": "deep"]]]
        XCTAssertEqual(MqttManager.extractValue(from: json, keyPath: "a.b.c"), "deep")
    }

    func testIntermediateNodeNotADict_returnsNil() {
        let json: [String: Any] = ["a": 42]
        XCTAssertNil(MqttManager.extractValue(from: json, keyPath: "a.b"))
    }
}
