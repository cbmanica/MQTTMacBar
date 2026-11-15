import XCTest
@testable import MQTTMacBar

final class SubscriptionStatsTests: XCTestCase {
    private var stats: SubscriptionStats!
    private let id = UUID()

    override func setUp() {
        super.setUp()
        stats = SubscriptionStats()
    }

    private func ctx(topic: String = "t", raw: String = "v") -> MqttMessageContext {
        MqttMessageContext(topic: topic, rawMessage: raw, displayValue: raw, previousRawMessage: nil)
    }

    // MARK: recordMessage

    func testRecordMessage_incrementsCount() {
        stats.recordMessage(ctx(), id: id)
        stats.recordMessage(ctx(), id: id)
        XCTAssertEqual(stats.messageCount[id], 2)
    }

    func testRecordMessage_setsHasUnseen() {
        stats.recordMessage(ctx(), id: id)
        XCTAssertTrue(stats.hasUnseen[id] == true)
    }

    func testRecordMessage_storesLastContext() {
        let c = ctx(raw: "hello")
        stats.recordMessage(c, id: id)
        XCTAssertEqual(stats.lastContext[id]?.rawMessage, "hello")
    }

    func testRecordMessage_updatesLastReceived() {
        let before = Date()
        stats.recordMessage(ctx(), id: id)
        let after = Date()
        let received = stats.lastReceived[id]
        XCTAssertNotNil(received)
        XCTAssertTrue(received! >= before && received! <= after)
    }

    // MARK: markSeen

    func testMarkSeen_clearsUnseenFlag() {
        stats.recordMessage(ctx(), id: id)
        stats.markSeen(id)
        XCTAssertEqual(stats.hasUnseen[id], false)
    }

    func testMarkSeen_doesNotAffectOtherIDs() {
        let other = UUID()
        stats.recordMessage(ctx(), id: id)
        stats.recordMessage(ctx(), id: other)
        stats.markSeen(id)
        XCTAssertTrue(stats.hasUnseen[other] == true)
    }

    // MARK: markAllSeen

    func testMarkAllSeen_clearsAllFlags() {
        let id2 = UUID()
        stats.recordMessage(ctx(), id: id)
        stats.recordMessage(ctx(), id: id2)
        stats.markAllSeen()
        XCTAssertEqual(stats.hasUnseen[id], false)
        XCTAssertEqual(stats.hasUnseen[id2], false)
    }
}
