import XCTest
@testable import MQTTMacBar

final class MqttSubscriptionTests: XCTestCase {

    private func sub(_ topic: String) -> TopicSubscription {
        TopicSubscription(topic: topic)
    }

    // MARK: matchesTopic — exact match

    func testExactMatch() {
        XCTAssertTrue(MqttManager.matchesTopic(sub("home/temp"), incomingTopic: "home/temp"))
    }

    func testExactNoMatch() {
        XCTAssertFalse(MqttManager.matchesTopic(sub("home/temp"), incomingTopic: "home/humidity"))
    }

    // MARK: matchesTopic — wildcard

    func testWildcard_matchesChildTopic() {
        XCTAssertTrue(MqttManager.matchesTopic(sub("sensors/#"), incomingTopic: "sensors/temperature"))
    }

    func testWildcard_matchesDeepChildTopic() {
        XCTAssertTrue(MqttManager.matchesTopic(sub("sensors/#"), incomingTopic: "sensors/room1/temperature"))
    }

    func testWildcard_matchesExactPrefix() {
        XCTAssertTrue(MqttManager.matchesTopic(sub("sensors/#"), incomingTopic: "sensors"))
    }

    func testWildcard_doesNotMatchDifferentRoot() {
        XCTAssertFalse(MqttManager.matchesTopic(sub("sensors/#"), incomingTopic: "other/temperature"))
    }

    func testBareHash_matchesAnything() {
        XCTAssertTrue(MqttManager.matchesTopic(sub("#"), incomingTopic: "anything/at/all"))
    }

    func testNonWildcardTopicDoesNotMatchSubtopic() {
        XCTAssertFalse(MqttManager.matchesTopic(sub("sensors"), incomingTopic: "sensors/temp"))
    }
}
