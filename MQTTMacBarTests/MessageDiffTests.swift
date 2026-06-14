import XCTest
@testable import MQTTMacBar

final class MessageDiffTests: XCTestCase {

    // MARK: buildDiffLines

    func testBuildDiffLines_identicalStrings_returnsEmpty() {
        XCTAssertTrue(buildDiffLines(old: "hello", new: "hello").isEmpty)
    }

    func testBuildDiffLines_nilOld_returnsEmpty() {
        XCTAssertTrue(buildDiffLines(old: nil, new: "hello").isEmpty)
    }

    func testBuildDiffLines_plainStringChange_returnsSingleChangedLine() {
        let lines = buildDiffLines(old: "foo", new: "bar")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].kind, .changed)
        XCTAssertEqual(lines[0].text, "~ foo → bar")
    }

    func testBuildDiffLines_jsonValueChanged_returnsChangedKey() {
        let old = #"{"temp":20}"#
        let new = #"{"temp":25}"#
        let lines = buildDiffLines(old: old, new: new)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].kind, .changed)
        XCTAssertTrue(lines[0].text.contains("temp"))
        XCTAssertTrue(lines[0].text.contains("→"))
    }

    func testBuildDiffLines_jsonKeyAdded_returnsAddedLine() {
        let old = #"{"a":1}"#
        let new = #"{"a":1,"b":2}"#
        let lines = buildDiffLines(old: old, new: new)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].kind, .added)
        XCTAssertTrue(lines[0].text.hasPrefix("+ b:"))
    }

    func testBuildDiffLines_jsonKeyRemoved_returnsRemovedLine() {
        let old = #"{"a":1,"b":2}"#
        let new = #"{"a":1}"#
        let lines = buildDiffLines(old: old, new: new)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].kind, .removed)
        XCTAssertTrue(lines[0].text.hasPrefix("- b:"))
    }

    func testBuildDiffLines_jsonUnchangedKeys_omitted() {
        let old = #"{"a":1,"b":2}"#
        let new = #"{"a":1,"b":3}"#
        let lines = buildDiffLines(old: old, new: new)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].text.contains("b"))
    }

    // MARK: prettyPrintJSON

    func testPrettyPrintJSON_validJson_returnsFormatted() {
        let raw = #"{"key":"value"}"#
        let pretty = prettyPrintJSON(raw)
        XCTAssertTrue(pretty.contains("\n"))
        XCTAssertTrue(pretty.contains("key"))
    }

    func testPrettyPrintJSON_invalidJson_returnsOriginal() {
        let notJson = "not json at all"
        XCTAssertEqual(prettyPrintJSON(notJson), notJson)
    }

    func testPrettyPrintJSON_emptyObject_returnsFormatted() {
        let result = prettyPrintJSON("{}")
        XCTAssertTrue(result.contains("{"))
    }

    // MARK: anyToString

    func testAnyToString_string() {
        XCTAssertEqual(anyToString("hello"), "hello")
    }

    func testAnyToString_int() {
        XCTAssertEqual(anyToString(42), "42")
    }

    func testAnyToString_bool() {
        XCTAssertEqual(anyToString(true), "true")
    }

    func testAnyToString_double() {
        XCTAssertEqual(anyToString(3.14), "3.14")
    }

    func testAnyToString_dict_returnsJsonString() {
        let result = anyToString(["k": "v"])
        XCTAssertTrue(result.contains("k"))
        XCTAssertTrue(result.contains("v"))
    }

    func testAnyToString_array_returnsJsonString() {
        let result = anyToString([1, 2, 3])
        XCTAssertTrue(result.contains("1"))
        XCTAssertTrue(result.contains("3"))
    }
}
