import XCTest
@testable import MyCalendar

final class HexColorTests: XCTestCase {
    func testSixDigitHex() throws {
        let color = try XCTUnwrap(HexColor.components(from: "#FF8000"))
        XCTAssertEqual(color.red, 1, accuracy: 0.001)
        XCTAssertEqual(color.green, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(color.blue, 0, accuracy: 0.001)
        XCTAssertEqual(color.alpha, 1, accuracy: 0.001)
    }

    func testShortHexWithoutHash() throws {
        let color = try XCTUnwrap(HexColor.components(from: "0F0"))
        XCTAssertEqual(color.red, 0, accuracy: 0.001)
        XCTAssertEqual(color.green, 1, accuracy: 0.001)
        XCTAssertEqual(color.blue, 0, accuracy: 0.001)
    }

    func testEightDigitHexHasAlpha() throws {
        let color = try XCTUnwrap(HexColor.components(from: "#0A84FF80"))
        XCTAssertEqual(color.red, 10.0 / 255, accuracy: 0.001)
        XCTAssertEqual(color.alpha, 128.0 / 255, accuracy: 0.001)
    }

    func testInvalidHexReturnsNil() {
        XCTAssertNil(HexColor.components(from: ""))
        XCTAssertNil(HexColor.components(from: "#GG0000"))
        XCTAssertNil(HexColor.components(from: "12345"))
        XCTAssertNil(HexColor.components(from: "+12345"))
    }

    func testStringRoundTrip() throws {
        let color = try XCTUnwrap(HexColor.components(from: "#1C1C1E"))
        XCTAssertEqual(HexColor.string(red: color.red, green: color.green, blue: color.blue), "#1C1C1E")
        XCTAssertEqual(HexColor.string(red: 1, green: 0, blue: 0, alpha: 0.5), "#FF000080")
    }
}
