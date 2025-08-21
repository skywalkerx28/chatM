import XCTest
@testable import chatM

final class BinaryEncodingUtilsTests: XCTestCase {
    func testHexInitFailsOnOddLength() {
        XCTAssertNil(Data(hexString: "ABC"))
    }

    func testHexInitParsesValidString() {
        let data = Data(hexString: "0a0b")
        XCTAssertEqual(data, Data([0x0a, 0x0b]))
    }
}
