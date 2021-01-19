import XCTest
import SwiftLodePNG

final class SwiftLodePNGTests: XCTestCase {
	func testRoundTrip() {
		let image = RGBA8Image(width: 4, height: 4, data: Array(0..<64))
		XCTAssertEqual(image, try RGBA8Image(decoding: image.encode()))
	}

	func testCOW() {
		let image1 = RGBA8Image(width: 4, height: 4, data: Array(0..<64))
		var image2 = image1
		image2[x: 3, y: 2] = RGBA8(r: 255, g: 255, b: 255, a: 255)
		XCTAssertNotEqual(image1, image2)
		let arr = [UInt8](0..<64)
		RGBA8Image.withImage(data: arr, width: 4, height: 4) { img in
			XCTAssertEqual(img, image1)
			var img = img
			img[x: 3, y: 2] = RGBA8(r: 255, g: 255, b: 255, a: 255)
			XCTAssertEqual(img, image2)
		}
		XCTAssertEqual(arr, [UInt8](0..<64))
	}
	
	static var allTests = [
		("round trip image encode/decode", testRoundTrip),
		("COW-ness", testCOW),
	]
}
