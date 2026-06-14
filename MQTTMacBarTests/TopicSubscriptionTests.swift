import XCTest
@testable import MQTTMacBar

final class TopicSubscriptionTests: XCTestCase {

    // MARK: Codable round-trip

    func testRoundTrip_allFields() throws {
        let original = TopicSubscription(
            id: UUID(),
            topic: "home/temp",
            jsonKeyPath: "sensors.temperature",
            label: "Temp",
            showInMenuBar: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TopicSubscription.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.topic, original.topic)
        XCTAssertEqual(decoded.jsonKeyPath, original.jsonKeyPath)
        XCTAssertEqual(decoded.label, original.label)
        XCTAssertEqual(decoded.showInMenuBar, original.showInMenuBar)
    }

    func testLegacyDecode_missingShowInMenuBar_defaultsToTrue() throws {
        // Simulate JSON saved before showInMenuBar was added
        let legacyJSON = #"{"id":"00000000-0000-0000-0000-000000000001","topic":"test/topic"}"#
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(TopicSubscription.self, from: data)
        XCTAssertTrue(decoded.showInMenuBar)
    }

    // MARK: Empty-string normalization

    func testEmptyJsonKeyPath_storedAsNil() {
        let sub = TopicSubscription(topic: "t", jsonKeyPath: "")
        XCTAssertNil(sub.jsonKeyPath)
    }

    func testEmptyLabel_storedAsNil() {
        let sub = TopicSubscription(topic: "t", label: "   ")
        // Label with only whitespace: current code uses isEmpty, so "   " is NOT nil
        // This test documents current behavior — update if trimming is added
        XCTAssertNotNil(sub.label)
    }

    func testNonEmptyKeyPath_preserved() {
        let sub = TopicSubscription(topic: "t", jsonKeyPath: "a.b.c")
        XCTAssertEqual(sub.jsonKeyPath, "a.b.c")
    }

    // MARK: Equatable

    func testEquality_sameIDAndFields() {
        let id = UUID()
        let a = TopicSubscription(id: id, topic: "x")
        let b = TopicSubscription(id: id, topic: "x")
        XCTAssertEqual(a, b)
    }

    func testEquality_differentID_notEqual() {
        let a = TopicSubscription(id: UUID(), topic: "x")
        let b = TopicSubscription(id: UUID(), topic: "x")
        XCTAssertNotEqual(a, b)
    }
}
