import CLodePNG
import Foundation

var lodePNGVersion: String { return String(cString: LODEPNG_VERSION_STRING) }

public struct LodePNGImage<Color: LodePNGPixel> {
	/// An error from LodePNG
	public struct Error: LocalizedError {
		public var code: UInt32

		public var errorDescription: String {
			return String(cString: lodepng_error_text(code))
		}
	}

	static private func throwIfError(_ code: UInt32) throws {
		if code != 0 {
			throw Error(code: code)
		}
	}

	@usableFromInline class COWHelper {
		@usableFromInline var raw: UnsafeMutableRawPointer?
		@usableFromInline let width: UInt32
		@usableFromInline let height: UInt32

		/// Bytes in image
		@inlinable var size: Int {
			let bpp = Color.bpp
			if bpp % 8 == 0 {
				return Int(width) * Int(height) * (bpp / 8)
			} else {
				return (Int(width) * Int(height) * bpp + 7) / 8
			}
		}

		@inlinable init(width: UInt32, height: UInt32, raw: UnsafeMutableRawPointer?) {
			(self.width, self.height, self.raw) = (width, height, raw)
		}

		@usableFromInline init(copying other: COWHelper) {
			let size = other.size
			(width, height) = (other.width, other.height)
			raw = malloc(size)
			memcpy(raw, other.raw, size)
		}

		deinit {
			if let raw = raw {
				free(raw)
			}
		}
	}

	@usableFromInline var actual: COWHelper

	/// The image width
	@inlinable public var width: Int { return Int(actual.width) }
	/// The image height
	@inlinable public var height: Int { return Int(actual.height) }
	/// Bytes per image color value
	@inlinable public var bitDepth: Int { return Int(Color.bitDepth) }
	@inlinable mutating func makeMutable() {
		if !isKnownUniquelyReferenced(&actual) {
			actual = COWHelper(copying: actual)
		}
	}
	/// Raw storage
	@inlinable var raw: UnsafeMutableRawBufferPointer { return .init(start: actual.raw, count: actual.size) }
	/// Gives mutable access to raw storage
	@inlinable mutating func withUnsafeMutableBytes<Return>(_ execute: (UnsafeMutableRawBufferPointer) throws -> Return) rethrows -> Return {
		makeMutable()
		return try withExtendedLifetime(actual) { try execute(raw) }
	}
	/// Gives access to raw storage
	@inlinable func withUnsafeBytes<Return>(_ execute: (UnsafeRawBufferPointer) throws -> Return) rethrows -> Return {
		return try withExtendedLifetime(actual) { try execute(.init(raw)) }
	}

	@inlinable public subscript(x x: Int, y y: Int) -> Color {
		get {
			precondition((0..<width).contains(x) && (0..<height).contains(y))
			return Color(from: UnsafeRawBufferPointer(raw), index: x + y * width)
		}
		set {
			precondition((0..<width).contains(x) && (0..<height).contains(y))
			makeMutable()
			newValue.store(to: raw, index: x + y * width)
		}
	}

	/// Create a new image with the given dimensions
	public init(width: Int, height: Int, data: [UInt8]) {
		actual = .init(width: UInt32(width), height: UInt32(height), raw: nil)
		let size = actual.size
		precondition(data.count >= size)
		actual.raw = malloc(size)
		memcpy(actual.raw, data, size)
	}

	/// Create a new image with the given dimensions
	public init(width: Int, height: Int) {
		actual = .init(width: UInt32(width), height: UInt32(height), raw: nil)
		actual.raw = calloc(1, actual.size)
	}

	/// Decode the given buffer into a new image
	public init(decoding buffer: UnsafeRawBufferPointer) throws {
		let bound = buffer.bindMemory(to: UInt8.self)
		var tmpRaw: UnsafeMutablePointer<UInt8>? = nil
		var tmpWidth: UInt32 = 0
		var tmpHeight: UInt32 = 0
		try LodePNGImage.throwIfError(lodepng_decode_memory(&tmpRaw, &tmpWidth, &tmpHeight, bound.baseAddress, bound.count, Color.enumValue, Color.bitDepth))
		actual = .init(width: tmpWidth, height: tmpHeight, raw: .init(tmpRaw!))
	}

	/// Decode the given buffer into a new image
	@inlinable public init(decoding data: Data) throws {
		self = try data.withUnsafeBytes(Self.init(decoding:))
	}

	/// Decode the given buffer into a new image
	@inlinable public init(decoding data: [UInt8]) throws {
		self = try data.withUnsafeBytes(Self.init(decoding:))
	}

	/// Encode the image to an `UnsafeRawBufferPointer` which must be freed using `free()`
	public func encodeToUnsafePointer() throws -> UnsafeMutableRawBufferPointer {
		var out: UnsafeMutablePointer<UInt8>? = nil
		var outsize = 0
		let ptr = actual.raw!.bindMemory(to: UInt8.self, capacity: actual.size)
		try LodePNGImage.throwIfError(lodepng_encode_memory(&out, &outsize, ptr, actual.width, actual.height, Color.enumValue, Color.bitDepth))
		return UnsafeMutableRawBufferPointer(start: out.map(UnsafeMutableRawPointer.init), count: outsize)
	}

	/// Encode the image to a Foundation `Data`
	public func encode() throws -> Data {
		let ptr = try encodeToUnsafePointer()
		return Data(bytesNoCopy: ptr.baseAddress!, count: ptr.count, deallocator: .free)
	}

	@inlinable init(_ actual: COWHelper) {
		self.actual = actual
	}

	/// Temporarily create an image with the given storage (the image is only valid for the duration of `execute`)
	@inlinable public static func withImage<Result>(
		data: UnsafeRawBufferPointer, width: Int, height: Int,
		_ execute: (LodePNGImage) throws -> Result
	) rethrows -> Result {
		let ptr = UnsafeMutableRawPointer(mutating: data.baseAddress!) // COW will prevent modifications
		let image = COWHelper(width: UInt32(width), height: UInt32(height), raw: ptr)
		defer { image.raw = nil }
		precondition(data.count >= image.size)
		return try execute(.init(image))
	}

	/// Temporarily create an image with bytes from the given array (the image is only valid for the duration of `execute`)
	@inlinable public static func withImage<Result>(
		data: [UInt8], width: Int, height: Int,
		_ execute: (LodePNGImage) throws -> Result
	) rethrows -> Result {
		return try data.withUnsafeBytes { try withImage(data: $0, width: width, height: height, execute) }
	}

	/// Take ownership of the image's buffer, destroying it
	@inlinable public mutating func takeOwnershipOfBuffer() -> UnsafeMutableRawBufferPointer {
		makeMutable()
		let out = raw
		actual.raw = nil
		return out
	}
}

extension LodePNGImage: Equatable {
	public static func == (lhs: LodePNGImage, rhs: LodePNGImage) -> Bool {
		guard lhs.width == rhs.width && lhs.height == rhs.height else { return false }
		return lhs.withUnsafeBytes { lhsptr in
			return rhs.withUnsafeBytes { rhsptr in
				return memcmp(lhsptr.baseAddress!, rhsptr.baseAddress!, lhsptr.count) == 0
			}
		}
	}
}
