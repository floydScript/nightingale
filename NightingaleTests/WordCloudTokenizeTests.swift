import XCTest
@testable import Nightingale

final class WordCloudTokenizeTests: XCTestCase {

    func testBasicTokenization() {
        let tokens = WordCloudView.tokenize(
            ["苹果 苹果 香蕉"],
            limit: 10,
            stopWords: []
        )
        let dict = Dictionary(uniqueKeysWithValues: tokens.map { ($0.token, $0.count) })
        XCTAssertEqual(dict["苹果"], 2)
        XCTAssertEqual(dict["香蕉"], 1)
    }

    func testStopWordsAreRemoved() {
        let tokens = WordCloudView.tokenize(
            ["我 在 睡觉 的 时候 梦 到 苹果"],
            limit: 10,
            stopWords: ["我", "在", "的"]
        )
        let words = Set(tokens.map(\.token))
        XCTAssertFalse(words.contains("我"))
        XCTAssertFalse(words.contains("的"))
        XCTAssertFalse(words.contains("在"))
        XCTAssertTrue(words.contains("苹果"))
    }

    func testEmptyInputGivesEmptyOutput() {
        let tokens = WordCloudView.tokenize([], limit: 10, stopWords: [])
        XCTAssertTrue(tokens.isEmpty)
    }

    func testLimitIsRespected() {
        let text = (1...50).map { "w\($0)" }.joined(separator: " ")
        let tokens = WordCloudView.tokenize([text], limit: 10, stopWords: [])
        XCTAssertEqual(tokens.count, 10)
    }

    func testFontSizeScalesWithFrequency() {
        // "a" 出现 5 次，"b" 出现 1 次 → a 应有更大字号
        let tokens = WordCloudView.tokenize(
            ["a a a a a b"],
            limit: 10,
            stopWords: []
        )
        let dict = Dictionary(uniqueKeysWithValues: tokens.map { ($0.token, $0.fontSize) })
        guard let a = dict["a"], let b = dict["b"] else {
            return XCTFail("Missing tokens")
        }
        XCTAssertGreaterThan(a, b)
    }
}
