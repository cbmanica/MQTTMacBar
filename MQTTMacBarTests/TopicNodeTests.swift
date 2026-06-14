import XCTest
@testable import MQTTMacBar

final class TopicNodeTests: XCTestCase {

    // MARK: descendantLeafCount

    func testDescendantLeafCount_isolatedLeaf_returnsOne() {
        let leaf = TopicNode(segment: "temp", fullPath: "sensors/temp")
        XCTAssertEqual(leaf.descendantLeafCount, 1)
    }

    func testDescendantLeafCount_parentWithThreeLeaves_returnsThree() {
        let parent = TopicNode(segment: "sensors", fullPath: "sensors")
        parent.children = [
            TopicNode(segment: "a", fullPath: "sensors/a"),
            TopicNode(segment: "b", fullPath: "sensors/b"),
            TopicNode(segment: "c", fullPath: "sensors/c")
        ]
        XCTAssertEqual(parent.descendantLeafCount, 3)
    }

    func testDescendantLeafCount_twoLevelsDeep() {
        let root = TopicNode(segment: "root", fullPath: "root")
        let mid = TopicNode(segment: "mid", fullPath: "root/mid")
        mid.children = [
            TopicNode(segment: "x", fullPath: "root/mid/x"),
            TopicNode(segment: "y", fullPath: "root/mid/y")
        ]
        root.children = [mid]
        XCTAssertEqual(root.descendantLeafCount, 2)
    }

    // MARK: latestDescendantUpdate

    func testLatestDescendantUpdate_leaf_returnsOwnLastReceived() {
        let leaf = TopicNode(segment: "t", fullPath: "t")
        XCTAssertNil(leaf.latestDescendantUpdate)
        let now = Date()
        leaf.lastReceived = now
        XCTAssertEqual(leaf.latestDescendantUpdate, now)
    }

    func testLatestDescendantUpdate_picksMaxAmongChildren() {
        let parent = TopicNode(segment: "p", fullPath: "p")
        let older = TopicNode(segment: "a", fullPath: "p/a")
        let newer = TopicNode(segment: "b", fullPath: "p/b")
        let oldDate = Date(timeIntervalSinceNow: -100)
        let newDate = Date(timeIntervalSinceNow: -10)
        older.lastReceived = oldDate
        newer.lastReceived = newDate
        parent.children = [older, newer]
        XCTAssertEqual(parent.latestDescendantUpdate, newDate)
    }

    func testLatestDescendantUpdate_nilWhenNoLeafHasReceived() {
        let parent = TopicNode(segment: "p", fullPath: "p")
        parent.children = [
            TopicNode(segment: "a", fullPath: "p/a"),
            TopicNode(segment: "b", fullPath: "p/b")
        ]
        XCTAssertNil(parent.latestDescendantUpdate)
    }

    // MARK: childrenByTimeOrNil

    func testChildrenByTimeOrNil_nilWhenNoChildren() {
        let leaf = TopicNode(segment: "x", fullPath: "x")
        XCTAssertNil(leaf.childrenByTimeOrNil)
    }

    func testChildrenByTimeOrNil_sortedNewestFirst() {
        let parent = TopicNode(segment: "p", fullPath: "p")
        let old = TopicNode(segment: "old", fullPath: "p/old")
        let new = TopicNode(segment: "new", fullPath: "p/new")
        old.lastReceived = Date(timeIntervalSinceNow: -200)
        new.lastReceived = Date(timeIntervalSinceNow: -5)
        parent.children = [old, new]
        let sorted = parent.childrenByTimeOrNil
        XCTAssertEqual(sorted?.first?.segment, "new")
        XCTAssertEqual(sorted?.last?.segment, "old")
    }
}
